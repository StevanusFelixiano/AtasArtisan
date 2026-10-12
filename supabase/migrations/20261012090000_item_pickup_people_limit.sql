-- Per-item pickup, a people limit with share-only members, and a reminder to tap Atas confirmed.
--
-- Additive only, so shipped builds keep working: one new table, two new nullable/defaulted columns, new RPCs and
-- triggers. `mark_taken`, `join_group`, `leave_group`, `remove_member` and `group_preview` keep their signatures
-- (group_preview's row gains columns, which older decoders ignore).
--
-- * Pickup per item: `item_pickups` holds one row per food line someone has taken: an item of their own (whole, or
--   the pieces they keep of a shared one) or their claimed pieces of someone's shared item. `members.taken_at` is
--   still set, once every line of theirs is taken, so the board's count, older builds and "Fridge is clear" (#23)
--   read it as before. `mark_taken` (I've taken mine) now marks or clears every line at once.
-- * People limit: `groups.people_limit` (host included; null = no limit). Whoever joins while the group has that many
--   full members joins share-only (`members.share_only`): they can claim pieces, join splits and ask to share, but not
--   add items of their own. When a full member leaves or is removed, or the host raises the limit, the share-only
--   members are told a spot opened; the first of them to add an item of their own takes it.
-- * Atas reply reminder: 30 minutes after the host sends, if the order is still Sent, the host is reminded to tap
--   Atas confirmed (or Atas replied). Once per send; a re-send after edits can remind again.
begin;

-- ---------------------------------------------------------------- per-item pickup

create table public.item_pickups (
  item_id uuid not null references public.items on delete cascade,
  group_id uuid not null references public.groups on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  taken_at timestamptz not null default now(),
  primary key (item_id, user_id)
);
alter table public.item_pickups enable row level security;
revoke insert, update, delete on public.item_pickups from anon, authenticated;
create policy members_read on public.item_pickups for select to authenticated using (public.is_member(group_id));
create index on public.item_pickups (group_id);
alter publication supabase_realtime add table public.item_pickups;
alter table public.item_pickups replica identity full;

-- Whoever already said I've taken mine has taken every line.
insert into public.item_pickups (item_id, group_id, user_id, taken_at)
  select f.item_id, m.group_id, m.user_id, m.taken_at
  from public.members m
  cross join lateral (select i.id from public.items i where i.group_id = m.group_id and i.owner_id = m.user_id and i.qty > 0
                      union
                      select c.item_id from public.item_claims c where c.group_id = m.group_id and c.user_id = m.user_id and c.pieces > 0) f(item_id)
  where m.taken_at is not null
  on conflict do nothing;

-- The items a member has food from: their own (whole, or a shared one's pieces nobody claimed) and their claims.
create function public.food_items(g uuid, u uuid) returns setof uuid language sql stable security definer set search_path = '' as $$
  select i.id from public.items i where i.group_id = g and i.owner_id = u and i.qty > 0
  union
  select c.item_id from public.item_claims c where c.group_id = g and c.user_id = u and c.pieces > 0
$$;

-- After any mark: the member is taken once every line is; the last counted person tells the host the fridge is clear,
-- once per group. The caller holds the group row lock.
create function public.pickup_settle(r public.groups, u uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare all_taken boolean;
begin
  all_taken := not exists (select 1 from public.food_items(r.id, u) f(item_id)
                           where not exists (select 1 from public.item_pickups p where p.item_id = f.item_id and p.user_id = u));
  update public.members set taken_at = case when all_taken then coalesce(taken_at, now()) end
  where group_id = r.id and user_id = u;
  if all_taken
     and not exists (select 1 from public.members m where m.group_id = r.id and m.removed_at is null and m.taken_at is null
                     and public.has_food(r.id, m.user_id))
     and not exists (select 1 from public.notifications n where n.group_id = r.id and n.kind = 'fridge_clear') then
    perform public.notify(r.host_id, r.id, 'fridge_clear', 'Fridge is clear',
      'Everyone has taken their ' || r.name || ' food. Close the order when you’re ready.');
  end if;
end $$;

revoke execute on function public.food_items(uuid, uuid), public.pickup_settle(public.groups, uuid)
  from public, anon, authenticated;

-- I've taken mine (taken true) or Undo (taken false): every line of my food at once.
create or replace function public.mark_taken(g uuid, taken boolean) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; me uuid := (select auth.uid());
begin
  select * into r from public.groups where id = g for update;
  if not coalesce(public.is_member(g), false) then raise exception 'not a member'; end if;
  if r.state is distinct from 'delivered' then raise exception 'Pickup opens once the order is delivered'; end if;
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

-- One line of my food taken (true) or put back (false).
create function public.mark_item_taken(item uuid, taken boolean) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; g uuid; me uuid := (select auth.uid());
begin
  select i.group_id into g from public.items i where i.id = item;
  if g is null or not coalesce(public.is_member(g), false) then raise exception 'not found'; end if;
  select * into r from public.groups where id = g for update;
  if r.state is distinct from 'delivered' then raise exception 'Pickup opens once the order is delivered'; end if;
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

revoke execute on function public.mark_item_taken(uuid, boolean) from public, anon;
grant execute on function public.mark_item_taken(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------- people limit

alter table public.groups add column people_limit int check (people_limit between 2 and 50);
alter table public.members add column share_only boolean not null default false;
grant insert (people_limit), update (people_limit) on public.groups to authenticated;

-- Members who can add items of their own (the host is always one).
create function public.full_count(g uuid) returns int language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.members m where m.group_id = g and m.removed_at is null and not m.share_only
$$;

-- Tells the share-only members that they can add their own items now, while there's room.
create function public.notify_spot_open(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; u uuid; free int;
begin
  select * into r from public.groups where id = g;
  if r.state <> 'open' then return; end if;
  free := case when r.people_limit is null then null else r.people_limit - public.full_count(g) end;
  if free is not null and free <= 0 then return; end if;
  for u in select m.user_id from public.members m where m.group_id = g and m.removed_at is null and m.share_only loop
    perform public.notify(u, g, 'spot_open', 'A spot opened in ' || r.name,
      case when free is null then 'You can add your own items now.'
           when free = 1 then '1 spot is free now. The first to add their own item takes it.'
           else free || ' spots are free now. The first to add their own items take them.' end);
  end loop;
end $$;

revoke execute on function public.full_count(uuid), public.notify_spot_open(uuid) from public, anon, authenticated;

-- A share-only member's first item of their own takes a free spot, or is refused while the group is full.
create function public.take_seat() returns trigger language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  if not exists (select 1 from public.members m where m.group_id = new.group_id and m.user_id = new.owner_id
                 and m.removed_at is null and m.share_only) then
    return new;
  end if;
  -- Row lock: two share-only members adding at once can't both take the last spot.
  select * into r from public.groups where id = new.group_id for update;
  if r.people_limit is not null and public.full_count(new.group_id) >= r.people_limit then
    raise exception 'This group is full (% people). You can still join shared items.', r.people_limit;
  end if;
  update public.members set share_only = false where group_id = new.group_id and user_id = new.owner_id;
  return new;
end $$;

create trigger take_seat before insert on public.items for each row execute function public.take_seat();

-- The host raised or cleared the limit: tell share-only members there's room.
create function public.limit_changed() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.people_limit is null or new.people_limit > coalesce(old.people_limit, 0) then
    perform public.notify_spot_open(new.id);
  end if;
  return null;
end $$;

create trigger limit_changed after update of people_limit on public.groups
  for each row when (old.people_limit is distinct from new.people_limit) execute function public.limit_changed();

-- #1, with the limit: past it, people join share-only.
create or replace function public.join_group(code text) returns uuid language plpgsql security definer set search_path = '' as $$
declare g public.groups; me uuid := (select auth.uid()); seatless boolean;
begin
  select * into g from public.groups where groups.code = upper(join_group.code) and not personal for update;
  if g.id is null then raise exception 'This group link is not valid'; end if;
  if g.state <> 'open' then raise exception 'This group is no longer taking orders'; end if;
  seatless := g.people_limit is not null and public.full_count(g.id) >= g.people_limit;
  insert into public.members (group_id, user_id, share_only) values (g.id, me, seatless)
    on conflict (group_id, user_id) do update set removed_at = null, joined_at = now(), share_only = excluded.share_only
    where members.removed_at is not null;
  if found then
    perform public.notify(g.host_id, g.id, 'joined',
      public.display_name(me) || ' joined ' || g.name || case when seatless then ' to share' else '' end,
      (select count(*) from public.members m where m.group_id = g.id and m.removed_at is null) || ' members now · '
      || public.rp(public.group_subtotal(g.id)) || ' of Rp 200.000.');
  end if;
  return g.id;
end $$;

-- Current bodies (20261002232926_shares_pay_first_close) plus the spot-open notice.
create or replace function public.leave_group(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; me uuid := (select auth.uid()); was_full boolean;
begin
  select * into r from public.groups where id = g;
  if r.id is null or not coalesce(public.is_member(g), false) then raise exception 'not a member'; end if;
  if r.host_id = me then raise exception 'The host can cancel the group instead'; end if;
  if r.state <> 'open' then raise exception 'You can only leave while the group is open'; end if;
  select not share_only into was_full from public.members where group_id = g and user_id = me;
  delete from public.item_claims where group_id = g and user_id = me;
  delete from public.share_requests where group_id = g and requester_id = me and state = 'pending';
  delete from public.items where group_id = g and owner_id = me;
  update public.members set removed_at = now() where group_id = g and user_id = me;
  if was_full and r.people_limit is not null then perform public.notify_spot_open(g); end if;
end $$;

create or replace function public.remove_member(g uuid, u uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; what text; was_full boolean;
begin
  r := public.require_host(g, array['open', 'locked', 'edits']);
  if u = r.host_id then raise exception 'The host cannot remove themselves'; end if;
  select not share_only into was_full from public.members where group_id = g and user_id = u and removed_at is null;
  select string_agg(i.qty || '× ' || i.name, ', ' order by i.name) into what from public.items i where i.group_id = g and i.owner_id = u;
  delete from public.item_claims where group_id = g and user_id = u;
  delete from public.share_requests where group_id = g and requester_id = u and state = 'pending';
  delete from public.items where group_id = g and owner_id = u;
  update public.members set removed_at = now() where group_id = g and user_id = u and removed_at is null;
  if r.pay_rule = 'pay_first' and r.state = 'locked' and r.bill_final_at is not null then
    perform public.settle_pay_first(g);
  end if;
  perform public.notify(u, g, 'removed', 'You were removed from ' || r.name,
    public.display_name(r.host_id) || ' removed you'
    || case when what is null then '.' else ', so your items are out of the order: ' || what || '.' end);
  if coalesce(was_full, false) and r.people_limit is not null then perform public.notify_spot_open(g); end if;
end $$;

-- 2-6 join preview, plus the limit: how many can add items now, and whether I'd join share-only.
drop function public.group_preview(text);
create function public.group_preview(code text) returns table (
  id uuid, name text, host_name text, area text, delivery_at timestamptz, cutoff_at timestamptz,
  state text, members int, already_member boolean, pay_rule text, address_label text, subtotal int,
  host_phone text, host_avatar text, host_avatar_bg text, people_limit int, full_members int, share_only boolean)
language sql stable security definer set search_path = '' as $$
  select g.id, g.name, public.display_name(g.host_id), g.area, g.delivery_at, g.cutoff_at, g.state,
         (select count(*)::int from public.members m where m.group_id = g.id and m.removed_at is null),
         exists (select 1 from public.members m where m.group_id = g.id and m.user_id = (select auth.uid()) and m.removed_at is null),
         g.pay_rule, nullif(g.address_label, ''), public.group_subtotal(g.id),
         p.phone, p.avatar, p.avatar_bg, g.people_limit, public.full_count(g.id),
         coalesce((select m.share_only from public.members m
                   where m.group_id = g.id and m.user_id = (select auth.uid()) and m.removed_at is null),
                  g.people_limit is not null and public.full_count(g.id) >= g.people_limit)
  from public.groups g join public.profiles p on p.id = g.host_id
  where g.code = upper(group_preview.code) and not g.personal
$$;
revoke execute on function public.group_preview(text) from public, anon;
grant execute on function public.group_preview(text) to authenticated;

-- ---------------------------------------------------------------- Atas reply reminder

-- Hosts whose order has been Sent for 30 minutes without Atas confirmed: one reminder per send.
create function public.remind_atas_reply() returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  for r in select * from public.groups x
           where x.state = 'sent' and x.sent_at < now() - interval '30 minutes'
             and not exists (select 1 from public.notifications n
                             where n.group_id = x.id and n.kind = 'atas_reply' and n.created_at > x.sent_at) loop
    perform public.notify(r.host_id, r.id, 'atas_reply', 'Did Atas reply?',
      'Once Atas confirms ' || r.name || ' on WhatsApp, open the order and tap '
      || case when r.pay_rule = 'pay_first' and r.bill_final_at is not null then 'Atas confirmed'
              else 'Atas replied to enter the ongkir' end
      || ' so everyone knows it’s on.');
  end loop;
end $$;
revoke execute on function public.remind_atas_reply() from public, anon, authenticated;

select cron.schedule('ataste-atas-reply', '*/5 * * * *', 'select public.remind_atas_reply()');

commit;
