-- Ready, public groups, auto-kick at lock.
--
-- Additive only, so shipped builds keep working: three new columns with defaults or null, three new RPCs, one new
-- trigger function, and `lock_now` gains a call to `kick_empty` at its top. No signature changes, nothing dropped.
--
-- * A member with a stake (own item, claimed pieces, or a live split share) taps Ready: `members.ready_at`.
--   When every non-host member with a stake is ready, the host gets one `all_ready` notice
--   (`groups.all_ready_notified` stops a repeat until a non-host member changes their order again).
-- * Any change a signed-in user makes to items, claims, split shares or share requests clears that user's Ready in
--   that group. Only the actor: others whose bill moved keep theirs. No-op for cron and the service role.
-- * At lock (`lock_group`, `tick()`'s auto-lock, both through `lock_now`), members with no stake are taken off the
--   list before shared minimums are applied and before bills freeze. They are never payers in `group_bill_live_v`
--   (payers are members with items > 0), so nobody else's bill changes.
-- * `groups.is_public`: anyone signed in can find the group through `public_groups()` and join by its code.
begin;

alter table public.members add column ready_at timestamptz;
alter table public.groups
  add column is_public boolean not null default false,
  add column all_ready_notified boolean not null default false;

grant insert (is_public), update (is_public) on public.groups to authenticated;

-- ---------------------------------------------------------------- stake

-- Food on the bill (own item, claimed pieces) or a pending/accepted split share.
create or replace function public.has_stake(g uuid, u uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.has_food(g, u)
      or exists (select 1 from public.split_shares ss
                 join public.splits s on s.id = ss.split_id
                 join public.items i on i.id = s.item_id
                 where i.group_id = g and ss.user_id = u and s.state in ('pending', 'accepted'))
$$;

-- ---------------------------------------------------------------- ready

create or replace function public.set_ready(g uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.groups; me uuid := (select auth.uid()); n int; waiting int;
begin
  -- Row lock: two members tapping Ready at once must not both miss the "everyone" moment.
  select * into r from public.groups where id = g for update;
  if r.id is null or not coalesce(public.is_member(g), false) then raise exception 'You’re not in this group'; end if;
  if r.state <> 'open' then raise exception 'This order isn’t open any more'; end if;
  if not coalesce(public.has_stake(g, me), false) then raise exception 'Add something to your order first'; end if;
  update public.members set ready_at = coalesce(ready_at, now()) where group_id = g and user_id = me;
  select count(*)::int, count(*) filter (where m.ready_at is null)::int into n, waiting
  from public.members m
  where m.group_id = g and m.removed_at is null and m.user_id <> r.host_id and public.has_stake(g, m.user_id);
  if n > 0 and waiting = 0 and not r.all_ready_notified then
    update public.groups set all_ready_notified = true where id = g;
    perform public.notify(r.host_id, g, 'all_ready', 'Everyone’s ready',
      r.name || ': ' || case when n = 1 then public.display_name(me) || ' is ready'
                             else 'all ' || n || ' people are ready' end
      || '. Lock the order when you want.');
  end if;
end $$;

-- Clears the actor's Ready when they change anything they have in the group.
create or replace function public.unready_actor() returns trigger
language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); j jsonb; g uuid;
begin
  if me is null then return null; end if;
  j := to_jsonb(case when tg_op = 'DELETE' then old else new end);
  if tg_table_name = 'split_shares' then
    select i.group_id into g from public.splits s join public.items i on i.id = s.item_id
    where s.id = (j ->> 'split_id')::uuid;
  else
    g := (j ->> 'group_id')::uuid;
  end if;
  if g is null then return null; end if;
  update public.members set ready_at = null where group_id = g and user_id = me and ready_at is not null;
  update public.groups set all_ready_notified = false where id = g and all_ready_notified and host_id <> me;
  return null;
end $$;

create trigger unready_actor after insert or update or delete on public.items
  for each row execute function public.unready_actor();
create trigger unready_actor after insert or update or delete on public.item_claims
  for each row execute function public.unready_actor();
create trigger unready_actor after insert or update or delete on public.split_shares
  for each row execute function public.unready_actor();
create trigger unready_actor after insert or update or delete on public.share_requests
  for each row execute function public.unready_actor();

-- ---------------------------------------------------------------- kick at lock

create or replace function public.kick_empty(g uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.groups; u uuid;
begin
  select * into r from public.groups where id = g;
  for u in select m.user_id from public.members m
           where m.group_id = g and m.removed_at is null and m.user_id <> r.host_id
             and not public.has_stake(g, m.user_id) loop
    update public.members set removed_at = now() where group_id = g and user_id = u;
    perform public.notify(u, g, 'removed', r.name,
      'You had nothing in this order when it locked, so you were taken off the list.');
  end loop;
end $$;

-- Current body (20261008130000_share_min_all_claimed) plus `kick_empty` first: stake is judged on what members
-- had when the lock started, so an owner whose shared item comes off for too few joiners stays on the list.
create or replace function public.lock_now(g uuid, skip uuid)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare r public.groups; it record; c record; people int; owner_amt bigint;
begin
  select * into r from public.groups where id = g for update;
  perform public.kick_empty(g);
  if r.state = 'open' then
    for it in select i.*, (i.unit_price * i.qty)::bigint as total,
                     (select count(*)::int from public.item_claims x where x.item_id = i.id) as joiners,
                     (select coalesce(sum(x.pieces), 0)::int from public.item_claims x where x.item_id = i.id) as claimed
              from public.items i where i.group_id = g and i.share_pieces is not null and i.share_min is not null loop
      people := 1 + it.joiners;
      if people < it.share_min and it.claimed < it.share_pieces - greatest(1, coalesce(it.share_keep, 1)) then
        perform public.notify(it.owner_id, g, 'share_min_not_met', it.name || ' came off',
          'Only ' || people || ' of ' || it.share_min || ' people joined before ' || r.name
          || ' locked, so it’s off the order. Nobody pays for it.');
        for c in select * from public.item_claims x where x.item_id = it.id loop
          perform public.notify(c.user_id, g, 'share_min_not_met', it.name || ' is off',
            public.display_name(it.owner_id) || ' needed ' || it.share_min || ' people and ' || people || ' joined. Your '
            || public.piece_count(c.pieces) || case when c.pieces = 1 then ' is' else ' are' end || ' gone from your bill.');
        end loop;
        delete from public.item_claims where item_id = it.id;
        delete from public.items where id = it.id;
      else
        select it.total - coalesce(sum(it.total * x.pieces / it.share_pieces), 0) into owner_amt
        from public.item_claims x where x.item_id = it.id;
        perform public.notify(it.owner_id, g, 'share_locked_in', 'Your ' || it.name || ' is shared',
          people || ' people joined. You keep ' || (it.share_pieces - it.claimed) || ' of ' || it.share_pieces
          || ' pieces, ' || public.rp(owner_amt) || '.');
        for c in select * from public.item_claims x where x.item_id = it.id loop
          perform public.notify(c.user_id, g, 'share_locked_in', 'You’re in for ' || public.piece_count(c.pieces),
            it.name || ' is on. ' || public.rp(it.total * c.pieces / it.share_pieces) || ' is on your bill.');
        end loop;
      end if;
    end loop;
  end if;
  update public.groups set state = 'locked', locked_at = now() where id = g;
  if r.pay_rule = 'pay_first' then perform public.settle_pay_first(g); end if;
  perform public.notify_locked(g, skip);
end $function$;

-- ---------------------------------------------------------------- public groups

create or replace function public.public_groups()
returns table (id uuid, code text, name text, host_name text, host_avatar text, host_avatar_bg text, area text,
               cutoff_at timestamptz, delivery_at timestamptz, members int)
language sql stable security definer set search_path = '' as $$
  select g.id, g.code, g.name, public.display_name(g.host_id), p.avatar, p.avatar_bg, g.area, g.cutoff_at, g.delivery_at,
         (select count(*)::int from public.members m where m.group_id = g.id and m.removed_at is null)
  from public.groups g join public.profiles p on p.id = g.host_id
  where g.is_public and g.state = 'open' and not g.personal
    and not exists (select 1 from public.members m
                    where m.group_id = g.id and m.user_id = (select auth.uid()) and m.removed_at is null)
  order by g.cutoff_at nulls last, g.created_at
$$;

-- ---------------------------------------------------------------- grants

revoke execute on function public.has_stake(uuid, uuid), public.unready_actor(), public.kick_empty(uuid),
  public.lock_now(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.set_ready(uuid), public.public_groups() from public, anon;
grant execute on function public.set_ready(uuid), public.public_groups() to authenticated;

commit;
