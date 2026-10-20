-- Pickup stays open after the order is closed. The host can close as soon as everyone has paid (pickup never blocks
-- Close), and auto-close runs 3 days after delivery, so food can still be in the fridge on a Closed order.
--
-- Same signatures, so shipped builds keep working; they just stop hiding their controls a state early.
--
-- * `mark_taken`, `mark_item_taken` and `mark_split_taken` accept Delivered or Closed (before: Delivered only).
-- * `pickup_settle` sends "Fridge is clear" (#23) only while Delivered: its copy asks the host to close the order.
-- * `pickup_nudge` is unchanged: the host's reminders stop at Close.

create or replace function public.pickup_settle(r public.groups, u uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare all_taken boolean;
begin
  all_taken := not exists (select 1 from public.food_items(r.id, u) f(item_id)
                           where not exists (select 1 from public.item_pickups p where p.item_id = f.item_id and p.user_id = u));
  update public.members set taken_at = case when all_taken then coalesce(taken_at, now()) end
  where group_id = r.id and user_id = u;
  if all_taken and r.state = 'delivered'
     and not exists (select 1 from public.members m where m.group_id = r.id and m.removed_at is null and m.taken_at is null
                     and public.has_food(r.id, m.user_id))
     and not exists (select 1 from public.notifications n where n.group_id = r.id and n.kind = 'fridge_clear') then
    perform public.notify(r.host_id, r.id, 'fridge_clear', 'Fridge is clear',
      'Everyone has taken their ' || r.name || ' food. Close the order when you’re ready.');
  end if;
end $$;

create or replace function public.mark_taken(g uuid, taken boolean) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; me uuid := (select auth.uid());
begin
  select * into r from public.groups where id = g for update;
  if not coalesce(public.is_member(g), false) then raise exception 'not a member'; end if;
  if not coalesce(r.state in ('delivered', 'closed'), false) then raise exception 'Pickup opens once the order is delivered'; end if;
  if not coalesce(public.has_food(g, me), false) then raise exception 'You have no food in this order'; end if;
  if coalesce(taken, false) then
    insert into public.item_pickups (item_id, group_id, user_id)
      select f.item_id, g, me from public.food_items(g, me) f(item_id)
      on conflict (item_id, user_id) do nothing;
  else
    delete from public.item_pickups where group_id = g and user_id = me;
  end if;
  perform public.pickup_settle(r, me);
end $$;

create or replace function public.mark_item_taken(item uuid, taken boolean) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; g uuid; me uuid := (select auth.uid());
begin
  select i.group_id into g from public.items i where i.id = item;
  if g is null or not coalesce(public.is_member(g), false) then raise exception 'not found'; end if;
  select * into r from public.groups where id = g for update;
  if not coalesce(r.state in ('delivered', 'closed'), false) then raise exception 'Pickup opens once the order is delivered'; end if;
  if not exists (select 1 from public.food_items(g, me) f(item_id) where f.item_id = item) then
    raise exception 'This isn’t your food';
  end if;
  if coalesce(taken, false) then
    insert into public.item_pickups (item_id, group_id, user_id) values (item, g, me) on conflict (item_id, user_id) do nothing;
  else
    delete from public.item_pickups where item_id = item and user_id = me;
  end if;
  perform public.pickup_settle(r, me);
end $$;

create or replace function public.mark_split_taken(item uuid, holder uuid, taken boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.groups; g uuid; me uuid := (select auth.uid()); i public.items; h uuid; n int; told timestamptz;
begin
  select x.group_id into g from public.items x where x.id = item;
  if g is null or not coalesce(public.is_member(g), false) then raise exception 'not found'; end if;
  select * into r from public.groups where id = g for update;
  if not coalesce(r.state in ('delivered', 'closed'), false) then raise exception 'Pickup opens once the order is delivered'; end if;
  select * into i from public.items x where x.id = item;
  if i.share_pieces is null or not exists (select 1 from public.item_claims c where c.item_id = item and c.pieces > 0) then
    raise exception 'This item isn’t shared';
  end if;
  if not exists (select 1 from public.split_holders(item) s(u) where s.u = me) then
    raise exception 'You’re not in this split';
  end if;
  if holder is not null and not exists (select 1 from public.split_holders(item) s(u) where s.u = holder) then
    raise exception 'They’re not in this split';
  end if;
  for h in select s.u from public.split_holders(item) s(u) where holder is null or s.u = holder loop
    if coalesce(taken, false) then
      insert into public.item_pickups (item_id, group_id, user_id, marked_by)
        values (item, g, h, case when h = me then null else me end)
        on conflict (item_id, user_id) do nothing;
    else
      told := null;
      delete from public.item_pickups p where p.item_id = item and p.user_id = h returning p.notified_at into told;
      if told is not null and h <> me then
        n := public.split_pieces(item, h);
        -- #32 "Your Burnt Cheesecake 20 cm slices are back in the fridge"
        perform public.notify(h, g, 'split_put_back',
          'Your ' || i.name || ' ' || split_part(public.unit_count(n, i.name), ' ', 2)
            || case when n = 1 then ' is' else ' are' end || ' back in the fridge',
          public.display_name(me) || ' put your ' || n || ' ' || i.name || ' ' || split_part(public.unit_count(n, i.name), ' ', 2)
            || ' back. ' || case when n = 1 then 'It’s' else 'They’re' end || ' still yours to take.');
      end if;
    end if;
    perform public.pickup_settle(r, h);
  end loop;
end $$;
