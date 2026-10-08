-- Pickup (Claude Design "Ataste Screens 7 Pickup", 7-1 … 7-5, notifications #23 / #24). Once an order is
-- Delivered, each person with food in it says when they have taken it out of the office fridge. A self-report: the
-- host doesn't confirm it, it never changes the bill and never blocks Close order.
--
-- Additive only, so builds without Pickup are unaffected: two nullable columns on members (no default, no grant
-- change, nothing existing reads them), three new internal helpers, two new RPCs, two new notification kinds.
-- No existing function, view or column changes. members is already in the realtime publication with replica
-- identity full, so the app's members watcher refetches on every mark, undo and nudge.
--
-- Who counts ("X of N taken"): active members who own an item in the order or hold claimed pieces of a shared one,
-- the host included (owner's call, 2026-10-08).
-- "Fridge is clear" (#23) goes to the host once per group: the guard is the fridge_clear notification row itself, so
-- an undo followed by a re-take never sends it again.

-- ---------------------------------------------------------------- columns

alter table public.members
  add column taken_at timestamptz,          -- the member says their food is out of the fridge (null: not taken / undone)
  add column pickup_nudged_at timestamptz;  -- the host's pickup reminder (one per member; separate from nudged_at)

-- ---------------------------------------------------------------- helpers (internal)

-- The member has food in the order: an item of their own, or claimed pieces of someone's shared item.
create function public.has_food(g uuid, u uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.items i where i.group_id = g and i.owner_id = u and i.qty > 0)
      or exists (select 1 from public.item_claims c where c.group_id = g and c.user_id = u and c.pieces > 0)
$$;

-- "1 slice", "3 slices" for cakes, "2 pieces" for anything else (the unit word follows the item, board 7).
create function public.unit_count(n int, item text) returns text language sql immutable set search_path = '' as $$
  select n || ' ' || case when item ilike '%cake%' then case when n = 1 then 'slice' else 'slices' end
                          else case when n = 1 then 'piece' else 'pieces' end end
$$;

-- What the member has in the fridge: "Brioche Bun, English Muffin, Pretzel 120 gr and 3 slices of Burnt Cheesecake".
-- Whole items ("2× Name") first, then pieces of shared items, each by name; a shared item's owner keeps the pieces
-- nobody claimed (the whole item when none were). The app lists them the same way (GroupStore.food(of:)).
create function public.food_list(g uuid, u uuid) returns text language sql stable security definer set search_path = '' as $$
  with f as (
    select i.share_pieces is not null and cl.n > 0 as s, i.name as k,
           case when i.share_pieces is not null and cl.n > 0 then public.unit_count(i.share_pieces - cl.n, i.name) || ' of ' || i.name
                when i.qty > 1 then i.qty || '× ' || i.name
                else i.name end as t
    from public.items i
    cross join lateral (select coalesce(sum(c.pieces), 0)::int as n from public.item_claims c where c.item_id = i.id) cl
    where i.group_id = g and i.owner_id = u and i.qty > 0
    union all
    select true, i.name, public.unit_count(c.pieces, i.name) || ' of ' || i.name
    from public.item_claims c join public.items i on i.id = c.item_id
    where c.group_id = g and c.user_id = u and c.pieces > 0
  ),
  l as (select array_agg(t order by s, k, t) as a from f)
  select case when a is null then ''
              when cardinality(a) = 1 then a[1]
              else array_to_string(a[1:cardinality(a) - 1], ', ') || ' and ' || a[cardinality(a)] end
  from l
$$;

revoke execute on function public.has_food(uuid, uuid), public.unit_count(int, text), public.food_list(uuid, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------- RPCs

-- I've taken mine (taken true) or Undo (taken false), for my own food, while the order is Delivered. Undo sends
-- nothing. The last counted person to take theirs tells the host the fridge is clear, once per group. The group
-- row is locked first, so two people marking at the same moment can't both miss (or both send) the notice.
create function public.mark_taken(g uuid, taken boolean) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; me uuid := (select auth.uid());
begin
  select * into r from public.groups where id = g for update;
  if not coalesce(public.is_member(g), false) then raise exception 'not a member'; end if;
  if r.state is distinct from 'delivered' then raise exception 'Pickup opens once the order is delivered'; end if;
  if not coalesce(public.has_food(g, me), false) then raise exception 'You have no food in this order'; end if;
  if not coalesce(taken, false) then
    update public.members set taken_at = null where group_id = g and user_id = me;
    return;
  end if;
  update public.members set taken_at = coalesce(taken_at, now()) where group_id = g and user_id = me;
  if not exists (select 1 from public.members m where m.group_id = g and m.removed_at is null and m.taken_at is null
                 and public.has_food(g, m.user_id))
     and not exists (select 1 from public.notifications n where n.group_id = g and n.kind = 'fridge_clear') then
    perform public.notify(r.host_id, g, 'fridge_clear', 'Fridge is clear',
      'Everyone has taken their ' || r.name || ' food. Close the order when you’re ready.');
  end if;
end $$;

-- The host reminds someone whose food is still in the fridge. One reminder per member (the board then shows
-- "Nudged HH:MM"); it doesn't touch the payment nudge's nudged_at.
create function public.pickup_nudge(g uuid, u uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; m public.members;
begin
  r := public.require_host(g, array['delivered']);
  select * into m from public.members where group_id = g and user_id = u and removed_at is null;
  if m.user_id is null or m.taken_at is not null or not public.has_food(g, u) then return; end if;
  if m.pickup_nudged_at is not null then raise exception 'You already nudged them'; end if;
  update public.members set pickup_nudged_at = now() where group_id = g and user_id = u;
  perform public.notify(u, g, 'pickup_nudge',
    'Reminder from ' || public.display_name(r.host_id) || ': your food’s in the fridge',
    public.food_list(g, u) || '. Tap I’ve taken mine once you have it.');
end $$;

revoke execute on function public.mark_taken(uuid, boolean), public.pickup_nudge(uuid, uuid) from public, anon;
grant execute on function public.mark_taken(uuid, boolean), public.pickup_nudge(uuid, uuid) to authenticated;
