-- Shared items after lock (Claude Design "Ataste Screens 10 Split after lock", 10-1 … 10-5, notifications #31 / #32).
-- At pickup one person usually carries the whole cake out of the fridge and cuts it for everyone, so anyone holding
-- pieces of a shared item (the owner included) can now mark any holder's pieces of that item taken while the order is
-- Delivered, or put them back.
--
-- Additive only, so shipped builds keep working: two nullable columns on item_pickups, new functions, one cron job and
-- two new notification kinds. `mark_taken`, `mark_item_taken`, `pickup_settle` and `food_items` are unchanged; a
-- self-mark leaves marked_by null, as before, and older builds read every mark as a self-mark.
--
-- * `item_pickups.marked_by`: who marked the line when it wasn't the holder (null: the holder did). The app shows
--   "Taken by Rani · 12:40" from it.
-- * `item_pickups.notified_at`: when the holder was told (#31). The app shows a 4 s Undo after a mark, so the push goes
--   from a per-minute job, only for marks older than 4 s that are still there: an undone mark notifies nobody.
-- * Put back after #31 went out tells the holder their pieces are back (#32); before it, nothing is sent.
-- * Marking never touches a bill, never blocks Close order, and counts toward "Fridge is clear" like a self-mark
--   (pickup_settle runs for every holder it touches). It covers only pieces of that one item, never other food.
begin;

-- ---------------------------------------------------------------- columns

alter table public.item_pickups
  add column marked_by uuid references auth.users on delete set null,  -- someone else in the split marked it
  add column notified_at timestamptz;                                  -- #31 sent to the holder

-- ---------------------------------------------------------------- helpers (internal)

-- Who holds pieces of a shared item: the owner while they keep any (the pieces nobody claimed), and everyone with a
-- claim. Each of them has the item among their food_items, so a mark here settles exactly like their own.
create function public.split_holders(item uuid) returns setof uuid language sql stable security definer set search_path = '' as $$
  select m.user_id
  from public.items i
  join public.members m on m.group_id = i.group_id and m.removed_at is null
  where i.id = split_holders.item and i.share_pieces is not null
    and i.id in (select f.item_id from public.food_items(i.group_id, m.user_id) f(item_id))
    and (m.user_id <> i.owner_id
         or i.share_pieces > (select coalesce(sum(c.pieces), 0) from public.item_claims c where c.item_id = i.id))
$$;

-- How many pieces of a shared item `u` holds: the owner what nobody claimed, anyone else their claim.
create function public.split_pieces(item uuid, u uuid) returns int language sql stable security definer set search_path = '' as $$
  select case when i.owner_id = u
              then i.share_pieces - (select coalesce(sum(c.pieces), 0)::int from public.item_claims c where c.item_id = i.id)
              else (select coalesce(sum(c.pieces), 0)::int from public.item_claims c where c.item_id = i.id and c.user_id = u) end
  from public.items i where i.id = split_pieces.item
$$;

revoke execute on function public.split_holders(uuid), public.split_pieces(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- RPC

-- Mark a holder's pieces of a shared item I'm in taken (taken true) or put them back (false); `holder` null is every
-- holder at once ("I took the whole cheesecake"). Pickup only, like mark_item_taken. Marking someone else records me in
-- marked_by and sends nothing yet (split_taken_push does, after the app's Undo). Putting back someone else's pieces after
-- #31 went out sends #32.
create function public.mark_split_taken(item uuid, holder uuid, taken boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.groups; g uuid; me uuid := (select auth.uid()); i public.items; h uuid; n int; told timestamptz;
begin
  select x.group_id into g from public.items x where x.id = item;
  if g is null or not coalesce(public.is_member(g), false) then raise exception 'not found'; end if;
  select * into r from public.groups where id = g for update;
  if r.state is distinct from 'delivered' then raise exception 'Pickup opens once the order is delivered'; end if;
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

revoke execute on function public.mark_split_taken(uuid, uuid, boolean) from public, anon;
grant execute on function public.mark_split_taken(uuid, uuid, boolean) to authenticated;

-- ---------------------------------------------------------------- #31, after the Undo window

-- Each holder whose pieces someone else marked, once the mark is 4 s old and still there: one push, #31a when every
-- holder of that item is out of the fridge ("Putri took the Burnt Cheesecake 20 cm out of the fridge"), else #31b
-- ("Kevin took your Classic Brownie pieces").
create function public.split_taken_push() returns void language plpgsql security definer set search_path = '' as $$
declare p record; i public.items; who text; n int; unit text; whole boolean;
begin
  for p in select x.item_id, x.group_id, x.user_id, x.marked_by from public.item_pickups x
           where x.marked_by is not null and x.marked_by <> x.user_id and x.notified_at is null
             and x.taken_at <= now() - interval '4 seconds'
           for update skip locked loop
    select * into i from public.items where id = p.item_id;
    who := public.display_name(p.marked_by);
    n := public.split_pieces(p.item_id, p.user_id);
    unit := split_part(public.unit_count(n, i.name), ' ', 2);
    whole := not exists (select 1 from public.split_holders(p.item_id) s(u)
                         where not exists (select 1 from public.item_pickups y where y.item_id = p.item_id and y.user_id = s.u));
    if whole then
      perform public.notify(p.user_id, p.group_id, 'split_taken',
        who || ' took the ' || i.name || ' out of the fridge',
        'Your ' || public.unit_count(n, i.name) || case when n = 1 then ' is' else ' are' end || ' with ' || who || '.');
    else
      perform public.notify(p.user_id, p.group_id, 'split_taken',
        who || ' took your ' || i.name || ' ' || unit,
        'Your ' || n || ' ' || i.name || ' ' || unit || case when n = 1 then ' is' else ' are' end
          || ' out of the fridge, with ' || who || '.');
    end if;
    update public.item_pickups set notified_at = now() where item_id = p.item_id and user_id = p.user_id;
  end loop;
end $$;

revoke execute on function public.split_taken_push() from public, anon, authenticated;

select cron.schedule('ataste-split-push', '* * * * *', $$select public.split_taken_push()$$);

commit;
