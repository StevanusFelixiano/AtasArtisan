-- Testing fixes (Claude Design "Testing Fixes" board): A2 shared items as piece claims, E/G2 the bill and pay
-- first, H closing waits for payment.
--
-- Bill rules (decisions, 2026-10-02):
--   * Shared item: a joiner pays floor(price × n ÷ pieces); the owner pays the rest, so shares add up to the price.
--   * Ongkir − discount is split equally among active members whose items come to more than Rp 0. Each share is
--     truncated to Rp 100 (towards zero) and the host takes the remainder. No bill goes below Rp 0.
--   * Subtotal Rp 200.000 or more: ongkir is free (ongkir 0, discount 0), whatever the host types.
--   * A bill turns final (groups.bill_final_at): order first when the host confirms Atas's reply; pay first at
--     lock when the subtotal is Rp 200.000 or more, otherwise when the host enters the ongkir (set_bill).
--     Final bills are frozen into members.bill_items / bill_total.
--   * Close waits until every member with a bill has been marked paid.
--
-- Build 9 compatibility: groups.state keeps its eight values (the app decodes it strictly); pay first is read
-- from bill_final_at / ongkir_asked_at. splits / split_shares and their RPCs stay, but no longer feed the bill.

-- ---------------------------------------------------------------- columns

alter table public.groups
  add column bill_final_at timestamptz,     -- bills frozen; members may pay
  add column ongkir_asked_at timestamptz,   -- pay first: the host asked Atas for the ongkir
  add column ongkir_set_at timestamptz;     -- the host typed ongkir/discount (null: free ongkir or not entered)

alter table public.members
  add column bill_items int,                -- frozen items part of bill_total
  add column paid_total int;                -- what the host has confirmed received

alter table public.items
  add column share_pieces int check (share_pieces between 2 and 24),
  add column share_min int check (share_min between 2 and 24),
  add constraint shared_qty_one check (share_pieces is null or qty = 1),
  add constraint share_min_needs_pieces check (share_min is null or share_pieces is not null);

alter table public.notifications add column push boolean not null default true;

-- Backfill frozen bills from the current view before it is replaced, so their breakdown never moves.
update public.members m set bill_items = v.items
from public.group_bill_v v
where v.group_id = m.group_id and v.user_id = m.user_id and m.bill_total is not null;
update public.members set bill_items = bill_total where bill_total is not null and bill_items is null;
update public.members set paid_total = bill_total where paid_at is not null and bill_total is not null;
update public.groups g set bill_final_at = coalesce(g.confirmed_at, now())
where exists (select 1 from public.members m where m.group_id = g.id and m.bill_total is not null);

-- ---------------------------------------------------------------- claims and share requests

create table public.item_claims (
  item_id uuid not null references public.items on delete cascade,
  group_id uuid not null references public.groups on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  pieces int not null check (pieces between 1 and 24),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (item_id, user_id)
);
create index on public.item_claims (group_id);
create index on public.item_claims (user_id);
alter table public.item_claims enable row level security;
revoke insert, update, delete on public.item_claims from anon, authenticated;
create policy members_read on public.item_claims for select to authenticated using (public.is_member(group_id));

create table public.share_requests (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items on delete cascade,
  group_id uuid not null references public.groups on delete cascade,
  owner_id uuid not null references auth.users on delete cascade,
  requester_id uuid not null references auth.users on delete cascade,
  pieces int not null check (pieces between 2 and 24),
  mine int not null check (mine >= 1 and mine < pieces),
  state text not null default 'pending' check (state in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now()
);
create unique index one_pending_request on public.share_requests (item_id, requester_id) where state = 'pending';
create index on public.share_requests (group_id);
create index on public.share_requests (owner_id);
create index on public.share_requests (requester_id);
alter table public.share_requests enable row level security;
revoke insert, update, delete on public.share_requests from anon, authenticated;
create policy owner_and_requester on public.share_requests for select to authenticated
  using (owner_id = (select auth.uid()) or requester_id = (select auth.uid()));

alter publication supabase_realtime add table public.item_claims, public.share_requests;
alter table public.item_claims replica identity full;
alter table public.share_requests replica identity full;

-- Live percentage splits become claims on 12 pieces (12 × share, rounded), which is what they represent.
update public.items i set share_pieces = 12
where i.qty = 1 and exists (
  select 1 from public.splits s where s.item_id = i.id and s.state = 'accepted'
    and not exists (select 1 from public.split_shares x where x.split_id = s.id and x.accepted_at is null));
insert into public.item_claims (item_id, group_id, user_id, pieces)
select i.id, i.group_id, x.user_id, round(12 * x.pct / 100)::int
from public.items i
join public.splits s on s.item_id = i.id and s.state = 'accepted'
join public.split_shares x on x.split_id = s.id
where i.share_pieces = 12 and x.user_id <> i.owner_id and round(12 * x.pct / 100) >= 1
  and not exists (select 1 from public.split_shares y where y.split_id = s.id and y.accepted_at is null)
on conflict do nothing;
do $$ begin
  if exists (select 1 from public.item_claims c join public.items i on i.id = c.item_id
             group by i.id, i.share_pieces having sum(c.pieces) > i.share_pieces) then
    raise exception 'migrated claims exceed 12 pieces';
  end if;
end $$;

-- ---------------------------------------------------------------- the bill

-- What each member owes right now, before freezing. Delivery is added only once the bill is final.
create view public.group_bill_live_v with (security_invoker = true) as
with lines as (
  select i.group_id, i.id as item_id, i.owner_id, (i.unit_price * i.qty)::bigint as total, i.share_pieces
  from public.items i
),
joiner as (
  select l.group_id, l.item_id, c.user_id, (l.total * c.pieces / l.share_pieces)::bigint as amt
  from lines l join public.item_claims c on c.item_id = l.item_id
  where l.share_pieces is not null and c.user_id <> l.owner_id
),
portions as (
  select group_id, user_id, amt from joiner
  union all
  select l.group_id, l.owner_id, l.total - coalesce((select sum(j.amt) from joiner j where j.item_id = l.item_id), 0)
  from lines l
),
item_totals as (
  select group_id, user_id, sum(amt)::int as items from portions group by group_id, user_id
),
base as (
  select m.group_id, m.user_id, coalesce(t.items, 0) as items, g.host_id,
         g.bill_final_at is not null as final,
         coalesce(g.ongkir, 0) - coalesce(g.discount, 0) as net
  from public.members m
  join public.groups g on g.id = m.group_id
  left join item_totals t on t.group_id = m.group_id and t.user_id = m.user_id
  where m.removed_at is null
),
payers as (
  select group_id, count(*)::int as n from base where items > 0 group by group_id
),
member_share as (
  select b.*, p.n,
         case when not b.final or p.n is null or b.items = 0 or b.user_id = b.host_id then 0
              when b.net >= 0 then (b.net / p.n / 100) * 100
              else greatest(-(((-b.net) / p.n / 100) * 100), -b.items)
         end as s
  from base b left join payers p on p.group_id = b.group_id
)
select x.group_id, x.user_id, x.items,
       (case when x.user_id = x.host_id and x.final and x.n is not null
             then greatest(x.net - coalesce((select sum(y.s) from member_share y
                                             where y.group_id = x.group_id and y.user_id <> x.host_id), 0), -x.items)
             else x.s end)::int as delivery_share
from member_share x;

-- What the app reads. Final bills come from the frozen columns. The first seven columns keep their names and types
-- (build 9 reads them); the rest are appended.
create or replace view public.group_bill_v with (security_invoker = true) as
select m.group_id, m.user_id,
       case when m.bill_total is not null then coalesce(m.bill_items, l.items) else l.items end as items,
       (case when m.bill_total is not null then m.bill_total - coalesce(m.bill_items, l.items) else l.delivery_share end)::bigint
         as delivery_share,
       m.bill_total, m.proof_at, m.paid_at,
       g.bill_final_at is not null and m.bill_total is not null as is_final,
       m.paid_total,
       case when g.bill_final_at is null or m.bill_total is null then null
            when m.user_id = g.host_id or m.paid_at is not null then 0
            else greatest(m.bill_total - coalesce(m.paid_total, 0), 0) end as owed
from public.members m
join public.groups g on g.id = m.group_id
left join public.group_bill_live_v l on l.group_id = m.group_id and l.user_id = m.user_id
where m.removed_at is null;

-- ---------------------------------------------------------------- helpers (internal)

create function public.piece_count(n int) returns text language sql immutable set search_path = '' as $$
  select n || case when n = 1 then ' piece' else ' pieces' end
$$;

create function public.notify_quiet(u uuid, g uuid, k text, t text, b text) returns void
language sql security definer set search_path = '' as $$
  insert into public.notifications (user_id, group_id, kind, title, body, push) values (u, g, k, t, b, false)
$$;

-- Freeze every active member's bill from the live view. paid_total is what the host has confirmed so far: a
-- member is paid while their bill is at most that, and owes the difference when it grows (owed in group_bill_v).
create function public.freeze_bills(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; b record; t int;
begin
  update public.groups set bill_final_at = coalesce(bill_final_at, now()) where id = g returning * into r;
  for b in select * from public.group_bill_live_v v where v.group_id = g loop
    t := b.items + b.delivery_share;
    update public.members m set
      bill_items = b.items,
      bill_total = t,
      paid_at = case when m.user_id = r.host_id or t = 0 then coalesce(m.paid_at, now())
                     when m.paid_total is not null and t <= m.paid_total then coalesce(m.paid_at, now())
                     when m.paid_total is not null then null
                     else m.paid_at end,
      paid_total = case when m.user_id = r.host_id then t
                        when t = 0 and m.paid_total is null then 0
                        else m.paid_total end,
      proof_at = case when m.user_id <> r.host_id and t > 0 and m.paid_total is not null and t > m.paid_total
                      then null else m.proof_at end
    where m.group_id = g and m.user_id = b.user_id;
  end loop;
end $$;

-- Bills stop being final (pay first: edits requested, unlocked, or the subtotal fell under Rp 200.000).
-- Payments already confirmed stay in paid_at / paid_total and are compared when the bill freezes again.
create function public.unfreeze_bills(g uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.groups set bill_final_at = null where id = g;
  update public.members set bill_total = null, bill_items = null where group_id = g;
end $$;

-- Pay first, entering Locked: free ongkir at Rp 200.000 or more; under it, the host's entered ongkir if there is
-- one, otherwise the bill waits for set_bill. Returns whether the bills are final.
create function public.settle_pay_first(g uuid) returns boolean language plpgsql security definer set search_path = '' as $$
declare r public.groups; sub int;
begin
  select * into r from public.groups where id = g;
  sub := public.group_subtotal(g);
  if sub >= 200000 then
    update public.groups set ongkir = 0, discount = 0, ongkir_set_at = null where id = g;
  elsif r.ongkir_set_at is not null then
    update public.groups set discount = least(coalesce(discount, 0), sub + coalesce(ongkir, 0)) where id = g;
  else
    perform public.unfreeze_bills(g);
    return false;
  end if;
  perform public.freeze_bills(g);
  return true;
end $$;

-- One notice per member when a group locks.
create function public.notify_locked(g uuid, skip uuid) returns void
language sql security definer set search_path = '' as $$
  insert into public.notifications (user_id, group_id, kind, title, body)
  select m.user_id, r.id,
         case when r.pay_rule = 'pay_first' and r.bill_final_at is not null and m.user_id <> r.host_id
                   and coalesce(m.bill_total, 0) > 0 then 'bill_final' else 'locked' end,
         case when r.pay_rule = 'pay_first' and r.bill_final_at is not null and m.user_id <> r.host_id
                   and coalesce(m.bill_total, 0) > 0 then 'Your ' || r.name || ' bill is ready'
              else r.name || ' is locked' end,
         case when r.pay_rule <> 'pay_first'
                then case when m.user_id = r.host_id then 'Check the order, then send it to Atas.'
                          else public.display_name(r.host_id) || ' is checking the order. The order is in — pay when you can, once the bill is final.' end
              when m.user_id = r.host_id
                then case when r.bill_final_at is not null then 'Bills are final. Send the order once everyone has paid.'
                          else 'Ask Atas for the ongkir so everyone can pay.' end
              when r.bill_final_at is null
                then public.display_name(r.host_id) || ' is asking Atas for the ongkir. You can pay once your bill is final.'
              when coalesce(m.bill_total, 0) > 0
                then 'Pay ' || public.display_name(r.host_id) || ' ' || public.rp(m.bill_total) || ' so '
                     || public.display_name(r.host_id) || ' can send the order.'
              else public.display_name(r.host_id) || ' sends the order once everyone has paid.'
         end
  from public.groups r
  join public.members m on m.group_id = r.id
  where r.id = g and m.removed_at is null and m.user_id is distinct from skip
$$;

-- The one way a group gets locked (host Lock order and the cutoff in tick()). From Open it first removes shared
-- items whose minimum isn't met and tells everyone involved; then the state flips; pay first then settles.
create function public.lock_now(g uuid, skip uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; it record; c record; people int; owner_amt bigint;
begin
  select * into r from public.groups where id = g for update;
  if r.state = 'open' then
    for it in select i.*, (i.unit_price * i.qty)::bigint as total,
                     (select count(*)::int from public.item_claims x where x.item_id = i.id) as joiners,
                     (select coalesce(sum(x.pieces), 0)::int from public.item_claims x where x.item_id = i.id) as claimed
              from public.items i where i.group_id = g and i.share_pieces is not null and i.share_min is not null loop
      people := 1 + it.joiners;
      if people < it.share_min then
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
end $$;

-- Claim holders of a shared item that is deleted (owner removed it, left, was removed, or an edit round took it
-- out) hear it with the Stop sharing message. lock_now deletes the claims first, so it sends its own copy.
create function public.notify_share_gone() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.share_pieces is null or not exists (select 1 from public.groups where id = old.group_id) then return old; end if;
  perform public.notify(c.user_id, old.group_id, 'share_stopped',
    public.display_name(old.owner_id) || ' stopped sharing the ' || old.name,
    'Your ' || public.piece_count(c.pieces) || case when c.pieces = 1 then ' is' else ' are' end
    || ' off your bill. The ' || old.name || ' is no longer on the order.')
  from public.item_claims c where c.item_id = old.id;
  return old;
end $$;
create trigger notify_share_gone before delete on public.items for each row execute function public.notify_share_gone();

-- A migrated split item now speaks through notify_share_gone; the old notice would say the same twice.
create or replace function public.cancel_splits_of_item() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.share_pieces is not null or not exists (select 1 from public.groups where id = old.group_id) then return old; end if;
  perform public.notify(x.user_id, old.group_id, 'split_cancelled', old.name || ' split cancelled',
    old.name || ' was removed from the order, so your ' || public.rp(round(old.unit_price * old.qty * x.pct / 100)::bigint) || ' share is gone.')
  from public.splits s join public.split_shares x on x.split_id = s.id
  where s.item_id = old.id and s.state in ('pending', 'accepted') and x.user_id <> old.owner_id;
  return old;
end $$;

-- The payment flow is picked until the order locks.
create function public.guard_pay_rule() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.pay_rule is distinct from old.pay_rule and old.state <> 'open' then
    raise exception 'The payment flow can only change while the group is open';
  end if;
  return new;
end $$;
create trigger guard_pay_rule before update of pay_rule on public.groups for each row execute function public.guard_pay_rule();

-- In-app-only rows (push = false) are not sent to APNs.
create or replace trigger push_notification after insert on public.notifications
  for each row when (new.push) execute function public.push_notification();

-- ---------------------------------------------------------------- sharing (A2)

-- The owner shares an item, or edits pieces / minimum. Sharing sets the quantity to 1. min_people null = none.
create function public.share_item(item uuid, pieces int, min_people int default null) returns void
language plpgsql security definer set search_path = '' as $$
declare i public.items; r public.groups; me uuid := (select auth.uid()); claimed int; q record; left_ int; n int;
begin
  select * into i from public.items where id = item for update;
  if i.id is null or not coalesce(public.is_member(i.group_id), false) then raise exception 'not found'; end if;
  if i.owner_id is distinct from me then raise exception 'Only the owner can share this item'; end if;
  select * into r from public.groups where id = i.group_id;
  if r.state <> 'open' then raise exception 'Sharing can only change while the group is open'; end if;
  if pieces is null or pieces not between 2 and 24 then raise exception 'Pieces must be between 2 and 24'; end if;
  if min_people is not null and min_people not between 2 and 24 then
    raise exception 'The minimum must be between 2 and 24 people';
  end if;
  select coalesce(sum(c.pieces), 0) into claimed from public.item_claims c where c.item_id = item;
  if pieces < claimed then raise exception 'Pieces can’t go below the % already claimed', claimed; end if;
  update public.items set share_pieces = share_item.pieces, share_min = min_people, qty = 1 where id = item;
  if i.share_pieces is null then
    perform public.notify_group(i.group_id, me, 'item_shared', public.display_name(me) || ' is sharing a ' || i.name,
      pieces || ' pieces, ' || public.rp(round(i.unit_price::numeric / pieces)::bigint) || ' each. Claim yours before '
      || coalesce(public.wita_time(r.cutoff_at), 'the order locks') || '.');
    -- Whoever asked for this item gets their pieces claimed for them, as far as they fit.
    left_ := pieces - claimed;
    for q in select * from public.share_requests s where s.item_id = item and s.state = 'pending' order by s.created_at loop
      n := least(q.mine, left_);
      if n > 0 and exists (select 1 from public.members m where m.group_id = i.group_id and m.user_id = q.requester_id
                           and m.removed_at is null) then
        insert into public.item_claims (item_id, group_id, user_id, pieces) values (item, i.group_id, q.requester_id, n)
          on conflict (item_id, user_id) do update set pieces = excluded.pieces, updated_at = now();
        left_ := left_ - n;
        update public.share_requests set state = 'accepted' where id = q.id;
      else
        update public.share_requests set state = 'declined' where id = q.id;
      end if;
    end loop;
  end if;
end $$;

-- The owner stops sharing: claims are released, joiners told; the whole item stays on the owner's order.
create function public.unshare_item(item uuid) returns void language plpgsql security definer set search_path = '' as $$
declare i public.items; me uuid := (select auth.uid());
begin
  select * into i from public.items where id = item for update;
  if i.id is null or not coalesce(public.is_member(i.group_id), false) then raise exception 'not found'; end if;
  if i.owner_id is distinct from me then raise exception 'Only the owner can stop sharing this item'; end if;
  if not exists (select 1 from public.groups where id = i.group_id and state = 'open') then
    raise exception 'Sharing can only change while the group is open';
  end if;
  if i.share_pieces is null then return; end if;
  perform public.notify(c.user_id, i.group_id, 'share_stopped', public.display_name(me) || ' stopped sharing the ' || i.name,
    'Your ' || public.piece_count(c.pieces) || case when c.pieces = 1 then ' is' else ' are' end || ' off your bill. The '
    || i.name || ' stays on the order under ' || public.display_name(me) || '.')
  from public.item_claims c where c.item_id = item;
  delete from public.item_claims where item_id = item;
  update public.items set share_pieces = null, share_min = null where id = item;
end $$;

-- A member sets their claim on someone else's shared item; 0 withdraws it.
create function public.claim_pieces(item uuid, pieces int) returns void language plpgsql security definer set search_path = '' as $$
declare i public.items; me uuid := (select auth.uid()); others int; before int; left_ int;
begin
  select * into i from public.items where id = item for update;
  if i.id is null or not coalesce(public.is_member(i.group_id), false) then raise exception 'not found'; end if;
  if i.owner_id = me then raise exception 'You can’t claim pieces of your own item'; end if;
  if not exists (select 1 from public.groups where id = i.group_id and state = 'open') then
    raise exception 'Pieces can only be claimed while the group is open';
  end if;
  if i.share_pieces is null then raise exception 'This item isn’t shared'; end if;
  if pieces is null or pieces < 0 then raise exception 'Pieces can’t be negative'; end if;
  select coalesce(sum(c.pieces) filter (where c.user_id <> me), 0), coalesce(sum(c.pieces) filter (where c.user_id = me), 0)
    into others, before from public.item_claims c where c.item_id = item;
  if others + pieces > i.share_pieces then
    raise exception 'Only % left', public.piece_count(i.share_pieces - others);
  end if;
  if pieces = 0 then
    delete from public.item_claims where item_id = item and user_id = me;
    return;
  end if;
  insert into public.item_claims (item_id, group_id, user_id, pieces) values (item, i.group_id, me, claim_pieces.pieces)
    on conflict (item_id, user_id) do update set pieces = excluded.pieces, updated_at = now();
  if pieces <> before then
    left_ := i.share_pieces - others - pieces;
    perform public.notify_quiet(i.owner_id, i.group_id, 'piece_claimed',
      public.display_name(me) || ' claimed ' || public.piece_count(pieces),
      'Of your ' || i.name || ' · ' || left_ || ' left');
  end if;
end $$;

-- Any member asks an item's owner to share it: `pieces` in all, `mine` of them for the asker. Returns the request.
create function public.ask_to_share(item uuid, pieces int, mine int) returns uuid language plpgsql security definer set search_path = '' as $$
declare i public.items; me uuid := (select auth.uid()); req uuid; inserted boolean;
begin
  select * into i from public.items where id = item;
  if i.id is null or not coalesce(public.is_member(i.group_id), false) then raise exception 'not found'; end if;
  if i.owner_id = me then raise exception 'This is your own item. Share it from its row'; end if;
  if not exists (select 1 from public.groups where id = i.group_id and state = 'open') then
    raise exception 'Sharing can only change while the group is open';
  end if;
  if i.share_pieces is not null then raise exception 'It’s already shared. Claim pieces instead'; end if;
  if pieces is null or pieces not between 2 and 24 then raise exception 'Pieces must be between 2 and 24'; end if;
  if mine is null or mine < 1 or mine >= pieces then raise exception 'Ask for between 1 and % pieces', pieces - 1; end if;
  insert into public.share_requests (item_id, group_id, owner_id, requester_id, pieces, mine)
    values (item, i.group_id, i.owner_id, me, ask_to_share.pieces, ask_to_share.mine)
    on conflict (item_id, requester_id) where state = 'pending'
    do update set pieces = excluded.pieces, mine = excluded.mine
    returning id, (xmax = 0) into req, inserted;
  if inserted then
    perform public.notify(i.owner_id, i.group_id, 'share_asked',
      public.display_name(me) || ' wants to share your ' || i.name,
      'Tap to share it in ' || public.piece_count(pieces) || '.');
  end if;
  return req;
end $$;

-- The owner answers "Not this time".
create function public.decline_share_request(request uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.share_requests set state = 'declined'
  where id = request and state = 'pending' and owner_id = (select auth.uid());
  if not found then raise exception 'There is no request to answer'; end if;
end $$;

-- Old split answers: only while the group is open, like proposing.
create or replace function public.respond_split(split uuid, accept boolean) returns void language plpgsql security definer set search_path = '' as $$
declare sp public.splits; i public.items; me uuid := (select auth.uid());
begin
  select * into sp from public.splits where id = split and state = 'pending';
  select * into i from public.items where id = sp.item_id;
  if sp.id is null or i.owner_id is distinct from me then raise exception 'not yours to answer'; end if;
  if not exists (select 1 from public.groups where id = i.group_id and state = 'open') then
    raise exception 'Splits can only be answered while the group is open';
  end if;
  if accept then
    update public.splits set state = 'accepted' where id = split;
    update public.split_shares set accepted_at = now() where split_id = split and user_id in (me, sp.proposer_id);
    perform public.notify(x.user_id, i.group_id, 'split_invited', public.display_name(sp.proposer_id) || ' invited you to share ' || i.name,
      'Your share: ' || trim_scale(x.pct)::text || '% · ' || public.rp(round(i.unit_price * i.qty * x.pct / 100)::bigint) || '.')
    from public.split_shares x where x.split_id = split and x.accepted_at is null;
  else
    update public.splits set state = 'declined' where id = split;
  end if;
  perform public.notify_split_answer(sp, i, me, accept);
end $$;

create or replace function public.answer_share(split uuid, accept boolean) returns void language plpgsql security definer set search_path = '' as $$
declare sp public.splits; i public.items; me uuid := (select auth.uid());
begin
  select * into sp from public.splits where id = split and state = 'accepted';
  select * into i from public.items where id = sp.item_id;
  if sp.id is null or not exists (select 1 from public.split_shares where split_id = split and user_id = me) then
    raise exception 'not part of this split';
  end if;
  if not exists (select 1 from public.groups where id = i.group_id and state = 'open') then
    raise exception 'Splits can only be answered while the group is open';
  end if;
  if accept then
    update public.split_shares set accepted_at = now() where split_id = split and user_id = me;
  else
    update public.splits set state = 'declined' where id = split;
  end if;
  perform public.notify_split_answer(sp, i, me, accept);
end $$;

-- ---------------------------------------------------------------- joining, leaving, locking

create or replace function public.leave_group(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; me uuid := (select auth.uid());
begin
  select * into r from public.groups where id = g;
  if r.id is null or not coalesce(public.is_member(g), false) then raise exception 'not a member'; end if;
  if r.host_id = me then raise exception 'The host can cancel the group instead'; end if;
  if r.state <> 'open' then raise exception 'You can only leave while the group is open'; end if;
  delete from public.item_claims where group_id = g and user_id = me;
  delete from public.share_requests where group_id = g and requester_id = me and state = 'pending';
  delete from public.items where group_id = g and owner_id = me;
  update public.members set removed_at = now() where group_id = g and user_id = me;
end $$;

create or replace function public.remove_member(g uuid, u uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; what text;
begin
  r := public.require_host(g, array['open', 'locked', 'edits']);
  if u = r.host_id then raise exception 'The host cannot remove themselves'; end if;
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
end $$;

create or replace function public.lock_group(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  r := public.require_host(g, array['open', 'edits']);
  if exists (select 1 from public.items where group_id = g and flagged_at is not null) then
    raise exception 'Some requested edits are not done yet';
  end if;
  perform public.lock_now(g, r.host_id);
end $$;

create or replace function public.unlock_group(g uuid, new_cutoff timestamptz default null) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  r := public.require_host(g, array['locked']);
  if r.pay_rule = 'pay_first' and r.bill_final_at is not null then perform public.unfreeze_bills(g); end if;
  update public.groups set state = 'open', cutoff_at = new_cutoff, cutoff_reminded = false where id = g;
  perform public.notify_group(g, r.host_id, 'unlocked', public.display_name(r.host_id) || ' unlocked ' || r.name,
    case when new_cutoff is null then 'Add or change items until it locks again.'
         else 'New cutoff ' || public.wita_time(new_cutoff) || '. Add or change items until then.' end);
end $$;

create or replace function public.request_edit(item uuid, reason text) returns void language plpgsql security definer set search_path = '' as $$
declare i public.items; r public.groups;
begin
  select * into i from public.items where id = item;
  if i.id is null then raise exception 'unknown item'; end if;
  r := public.require_host(i.group_id, array['locked', 'edits']);
  if r.pay_rule = 'pay_first' and r.bill_final_at is not null then perform public.unfreeze_bills(i.group_id); end if;
  update public.items set flag_reason = left(coalesce(reason, ''), 140), flagged_at = now() where id = item;
  update public.groups set state = 'edits' where id = i.group_id;
  update public.members set done_editing_at = null where group_id = i.group_id and user_id = i.owner_id;
  perform public.notify(i.owner_id, i.group_id, 'edit_requested', public.display_name(r.host_id) || ' asked you to edit an item',
    i.name || ': ' || coalesce('“' || nullif(left(reason, 140), '') || '”', 'please swap or remove it.'));
end $$;

-- ---------------------------------------------------------------- the ongkir (E) and Atas

-- Pay first: the host tapped "Ask Atas for ongkir" (step meta "Asked 13:05").
create function public.mark_ongkir_asked(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  r := public.require_host(g, array['locked']);
  if r.pay_rule <> 'pay_first' then raise exception 'Only pay-first groups ask Atas for the ongkir first'; end if;
  update public.groups set ongkir_asked_at = now() where id = g;
end $$;

-- Pay first, before sending: the host enters what Atas replied (screen E). Null counts as 0. Can be called again
-- until the order is sent; members who already paid then owe only the difference.
create function public.set_bill(g uuid, ongkir int, discount int) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; sub int; o int := coalesce(ongkir, 0); d int := coalesce(discount, 0); host text; b record; before jsonb;
begin
  r := public.require_host(g, array['locked']);
  if r.pay_rule <> 'pay_first' then raise exception 'Only pay-first groups enter the ongkir before sending'; end if;
  if o < 0 or d < 0 then raise exception 'amounts cannot be negative'; end if;
  if o > 9999999 or d > 9999999 then raise exception 'Amounts can be at most Rp 9.999.999'; end if;
  sub := public.group_subtotal(g);
  if sub >= 200000 then o := 0; d := 0; end if;
  d := least(d, sub + o);
  select jsonb_object_agg(user_id, bill_total) into before from public.members where group_id = g and removed_at is null;
  update public.groups set ongkir = o, discount = d,
    ongkir_set_at = case when sub >= 200000 then null else now() end where id = g;
  perform public.freeze_bills(g);
  host := public.display_name(r.host_id);
  for b in select v.user_id, v.bill_total, v.owed from public.group_bill_v v
           where v.group_id = g and v.user_id <> r.host_id and v.owed > 0
             and (before ->> v.user_id::text)::int is distinct from v.bill_total loop
    perform public.notify(b.user_id, g, 'bill_final', 'Your ' || r.name || ' bill is ready',
      'Pay ' || host || ' ' || public.rp(b.owed) || ' so ' || host || ' can send the order.');
  end loop;
end $$;

-- Atas confirmed. Order first (or pay first sent before the ongkir was in): sets ongkir/discount (null = 0, free
-- at Rp 200.000 or more) and freezes the bills. Pay first with final bills: just records the confirmation.
create or replace function public.confirm_atas(g uuid, ongkir int, discount int) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.groups; b record; host text; bank text; sub int; o int := coalesce(ongkir, 0); d int := coalesce(discount, 0);
begin
  r := public.require_host(g, array['sent']);
  if r.bill_final_at is not null then
    update public.groups set state = 'confirmed', confirmed_at = now() where id = g;
    return;
  end if;
  if o < 0 or d < 0 then raise exception 'amounts cannot be negative'; end if;
  if o > 9999999 or d > 9999999 then raise exception 'Amounts can be at most Rp 9.999.999'; end if;
  sub := public.group_subtotal(g);
  if sub >= 200000 then o := 0; d := 0; end if;
  d := least(d, sub + o);
  update public.groups set state = 'confirmed', confirmed_at = now(), ongkir = o, discount = d,
    ongkir_set_at = case when sub >= 200000 then null else now() end where id = g;
  perform public.freeze_bills(g);
  host := public.display_name(r.host_id);
  bank := public.payout_label(r);
  for b in select * from public.group_bill_v v where v.group_id = g and v.user_id <> r.host_id and v.owed > 0 loop
    perform public.notify(b.user_id, g, 'bill_final',
      'Atas confirmed — your bill is final: ' || public.rp(b.owed),
      case when r.pay_rule = 'pay_first' then 'Pay now so ' || host || ' can order.'
           else 'The order is in — pay when you can.' || coalesce(' Transfer to ' || host || ', ' || bank || '.', '') end);
  end loop;
end $$;

-- ---------------------------------------------------------------- payments (G2, H)

-- A member says they paid. Any time their bill is final, until the group is cancelled.
create or replace function public.claim_paid(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; me uuid := (select auth.uid()); v record; receipt boolean;
begin
  select * into r from public.groups where id = g;
  select * into v from public.group_bill_v b where b.group_id = g and b.user_id = me;
  if v.user_id is null then raise exception 'not a member'; end if;
  if not coalesce(v.is_final, false) or r.state = 'cancelled' then raise exception 'The bill is not final yet'; end if;
  update public.members set proof_at = now() where group_id = g and user_id = me;
  receipt := exists (select 1 from storage.objects o where o.bucket_id = 'receipts' and o.name = g::text || '/' || me::text || '.jpg');
  perform public.notify(r.host_id, g, 'member_paid',
    public.display_name(me) || ' says they’ve paid ' || public.rp(coalesce(nullif(v.owed, 0), v.bill_total, 0)),
    case when receipt then 'Receipt attached. ' else '' end || 'Check ' || coalesce(public.payout_label(r), 'your account') || ' and mark it paid.');
end $$;

-- The host marks a member paid (after a receipt, or cash with no claim).
create or replace function public.confirm_paid(g uuid, u uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; m public.members; amount int; host text;
begin
  r := public.require_host(g, array['locked', 'sent', 'confirmed', 'delivered', 'closed']);
  if r.bill_final_at is null then raise exception 'The bill is not final yet'; end if;
  select * into m from public.members where group_id = g and user_id = u and removed_at is null;
  if m.user_id is null or m.paid_at is not null then return; end if;
  amount := greatest(coalesce(m.bill_total, 0) - coalesce(m.paid_total, 0), 0);
  update public.members set paid_at = now(), paid_total = bill_total where group_id = g and user_id = u;
  host := public.display_name(r.host_id);
  if m.proof_at is null then
    perform public.notify(u, g, 'payment_confirmed', host || ' marked your ' || public.rp(amount) || ' as paid',
      'Nothing left to pay for ' || r.name || '.');
  else
    perform public.notify(u, g, 'payment_confirmed', host || ' confirmed your payment',
      public.rp(amount) || ' received. You’re all set for ' || to_char(r.delivery_at at time zone 'Asia/Makassar', 'FMDay') || '.');
  end if;
  if not exists (select 1 from public.members where group_id = g and removed_at is null and user_id <> r.host_id
                 and coalesce(bill_total, 0) > 0 and paid_at is null) then
    if r.pay_rule = 'pay_first' and r.state = 'locked' then
      perform public.notify(r.host_id, g, 'everyone_paid', 'Everyone has paid',
        'Send the ' || r.name || ' order to Atas before 15:00.');
    else
      perform public.notify(r.host_id, g, 'everyone_paid', 'Everyone has paid',
        public.rp((select coalesce(sum(bill_total), 0) from public.members where group_id = g and removed_at is null and user_id <> r.host_id))
        || ' collected for ' || r.name || '.');
    end if;
  end if;
end $$;

create or replace function public.reject_paid(g uuid, u uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; m public.members;
begin
  r := public.require_host(g, array['locked', 'sent', 'confirmed', 'delivered', 'closed']);
  if r.bill_final_at is null then raise exception 'The bill is not final yet'; end if;
  update public.members set proof_at = null where group_id = g and user_id = u and paid_at is null and proof_at is not null
    returning * into m;
  if m.user_id is null then raise exception 'There is no payment claim to reject'; end if;
  perform public.notify(u, g, 'payment_not_received', public.display_name(r.host_id) || ' hasn’t received your payment yet',
    public.rp(greatest(coalesce(m.bill_total, 0) - coalesce(m.paid_total, 0), 0)) || ' for ' || r.name || '. Check the transfer'
    || coalesce(' to ' || public.payout_label(r) || ' ' || public.payout_number(r), '') || ' and tap “I’ve paid” again.');
end $$;

-- One reminder per person every 4 hours.
create or replace function public.nudge(g uuid, u uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; m public.members; amount int; host text;
begin
  r := public.require_host(g, array['locked', 'sent', 'confirmed', 'delivered', 'closed']);
  if r.bill_final_at is null then raise exception 'The bill is not final yet'; end if;
  select * into m from public.members where group_id = g and user_id = u and removed_at is null;
  if m.user_id is null or m.paid_at is not null then return; end if;
  if m.nudged_at > now() - interval '4 hours' then raise exception 'You nudged them less than 4 hours ago'; end if;
  amount := greatest(coalesce(m.bill_total, 0) - coalesce(m.paid_total, 0), 0);
  host := public.display_name(r.host_id);
  update public.members set nudged_at = now() where group_id = g and user_id = u;
  if r.state = 'delivered' then
    perform public.notify(u, g, 'nudge', host || ' is waiting for ' || public.rp(amount),
      r.name || ' has arrived. Pay so ' || host || ' can close it.');
  else
    perform public.notify(u, g, 'nudge', 'Reminder from ' || host || ': ' || public.rp(amount),
      r.name || ' is waiting on your payment.' || coalesce(' ' || public.payout_label(r) || ' ' || public.payout_number(r) || '.', ''));
  end if;
end $$;

-- H: closing waits for every payment, so an older app can't close early either.
create or replace function public.close_group(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  r := public.require_host(g, array['delivered']);
  if exists (select 1 from public.members where group_id = g and removed_at is null and user_id <> r.host_id
             and coalesce(bill_total, 0) > 0 and paid_at is null) then
    raise exception 'Everyone has to pay before the order can be closed';
  end if;
  update public.groups set state = 'closed', closed_at = now() where id = g;
  perform public.notify_group(g, r.host_id, 'closed', r.name || ' is closed', 'Thanks for ordering together. Reorder anytime from History.');
end $$;

-- ---------------------------------------------------------------- automatic notices

create or replace function public.check_discount() returns trigger language plpgsql security definer set search_path = '' as $$
declare g public.groups; sub int;
begin
  select * into g from public.groups where id = coalesce(new.group_id, old.group_id);
  if g.id is null then return null; end if;
  sub := public.group_subtotal(g.id);
  if not g.discount_notified and not g.personal and sub >= 200000 then
    update public.groups set discount_notified = true where id = g.id;
    perform public.notify_group(g.id, null, 'discount_unlocked', 'Free ongkir unlocked!',
      g.name || ' hit ' || public.rp(sub) || ', so Atas delivers it for free.');
  end if;
  return null;
end $$;

-- Every minute: the 30-minute reminders (group, and owners of shared items short of their minimum), the
-- auto-lock at cutoff (same path as Lock order), and code cleanup.
create or replace function public.tick() returns void language plpgsql security definer set search_path = '' as $$
declare g public.groups; sub int; it record; short int;
begin
  for g in select * from public.groups where state = 'open' and not cutoff_reminded
           and cutoff_at between now() and now() + interval '30 minutes' loop
    update public.groups set cutoff_reminded = true where id = g.id;
    sub := public.group_subtotal(g.id);
    perform public.notify_group(g.id, null, 'cutoff_soon', g.name || ' locks in 30 minutes',
      'Get your order in before ' || public.wita_time(g.cutoff_at) || '.'
      || case when sub < 200000 then ' ' || public.rp(200000 - sub) || ' more for free ongkir.' else '' end);
    for it in select i.*, (select count(*)::int from public.item_claims x where x.item_id = i.id) as joiners
              from public.items i where i.group_id = g.id and i.share_min is not null loop
      short := it.share_min - 1 - it.joiners;
      if short > 0 then
        perform public.notify(it.owner_id, g.id, 'share_min_reminder', short || ' more for your ' || it.name,
          g.name || ' locks at ' || public.wita_time(g.cutoff_at) || '. Without ' || short
          || case when short = 1 then ' more person' else ' more people' end || ' it comes off the order.');
      end if;
    end loop;
  end loop;
  for g in select * from public.groups where state = 'open' and cutoff_at <= now() loop
    perform public.lock_now(g.id, null);
  end loop;
  delete from public.wa_codes where created_at < now() - interval '1 day';
end $$;

-- ---------------------------------------------------------------- live data

-- A pay-first group already locked at Rp 200.000 or more has final bills under the new rule (no notices).
do $$ declare x uuid; begin
  for x in select id from public.groups where pay_rule = 'pay_first' and state = 'locked' and bill_final_at is null
           and public.group_subtotal(id) >= 200000 loop
    perform public.settle_pay_first(x);
  end loop;
end $$;

-- ---------------------------------------------------------------- grants

-- notify_locked(public.groups, uuid) (20261001101000) is no longer called; notify_locked(uuid, uuid) replaces it.

revoke execute on function
  public.piece_count(int), public.notify_quiet(uuid, uuid, text, text, text), public.freeze_bills(uuid),
  public.unfreeze_bills(uuid), public.settle_pay_first(uuid), public.notify_locked(uuid, uuid), public.lock_now(uuid, uuid),
  public.notify_share_gone(), public.guard_pay_rule()
  from public, anon, authenticated;

revoke execute on function
  public.share_item(uuid, int, int), public.unshare_item(uuid), public.claim_pieces(uuid, int),
  public.ask_to_share(uuid, int, int), public.decline_share_request(uuid), public.mark_ongkir_asked(uuid),
  public.set_bill(uuid, int, int)
  from public, anon;
grant execute on function
  public.share_item(uuid, int, int), public.unshare_item(uuid), public.claim_pieces(uuid, int),
  public.ask_to_share(uuid, int, int), public.decline_share_request(uuid), public.mark_ongkir_asked(uuid),
  public.set_bill(uuid, int, int)
  to authenticated;
-- create or replace keeps the earlier grants of the replaced RPCs; restated so this file stands alone.
revoke execute on function
  public.respond_split(uuid, boolean), public.answer_share(uuid, boolean), public.leave_group(uuid),
  public.remove_member(uuid, uuid), public.lock_group(uuid), public.unlock_group(uuid, timestamptz),
  public.request_edit(uuid, text), public.confirm_atas(uuid, int, int), public.claim_paid(uuid),
  public.confirm_paid(uuid, uuid), public.reject_paid(uuid, uuid), public.nudge(uuid, uuid), public.close_group(uuid)
  from public, anon;
grant execute on function
  public.respond_split(uuid, boolean), public.answer_share(uuid, boolean), public.leave_group(uuid),
  public.remove_member(uuid, uuid), public.lock_group(uuid), public.unlock_group(uuid, timestamptz),
  public.request_edit(uuid, text), public.confirm_atas(uuid, int, int), public.claim_paid(uuid),
  public.confirm_paid(uuid, uuid), public.reject_paid(uuid, uuid), public.nudge(uuid, uuid), public.close_group(uuid)
  to authenticated;
revoke execute on function public.tick(), public.check_discount(), public.cancel_splits_of_item() from public, anon, authenticated;
grant select on public.group_bill_v, public.group_bill_live_v to authenticated;
revoke all on public.group_bill_v, public.group_bill_live_v from anon;
