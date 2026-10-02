-- Ataste order logic: the bill, the notifications, and every state change.
-- Each RPC is security definer with search_path '' and checks who may call it; EXECUTE is
-- revoked from public/anon and granted to authenticated at the bottom.

-- ---------------------------------------------------------------- the bill

-- Per member: their items, minus shares split away to others, plus shares of others' items,
-- plus an equal cut of (ongkir − discount) among everyone who owes something. Rounding
-- remainders go to the item owner (splits) and to the host (ongkir). Frozen into
-- members.bill_total when Atas confirms.
create view public.group_bill_v with (security_invoker = true) as
with lines as (
  select i.group_id, i.id as item_id, i.owner_id, i.unit_price * i.qty as total from public.items i
),
full_splits as (
  select s.id, s.item_id from public.splits s
  where s.state = 'accepted'
    and not exists (select 1 from public.split_shares x where x.split_id = s.id and x.accepted_at is null)
),
others as (
  select l.group_id, l.item_id, x.user_id, round(l.total * x.pct / 100)::int as amt
  from lines l join full_splits f on f.item_id = l.item_id
  join public.split_shares x on x.split_id = f.id
  where x.user_id <> l.owner_id
),
portions as (
  select group_id, user_id, amt from others
  union all
  select l.group_id, l.owner_id,
         l.total - coalesce((select sum(o.amt) from others o where o.item_id = l.item_id), 0)
  from lines l
),
item_totals as (
  select group_id, user_id, sum(amt)::int as items from portions group by group_id, user_id
),
payers as (
  select t.group_id, count(*) as n from item_totals t
  join public.members m on m.group_id = t.group_id and m.user_id = t.user_id and m.removed_at is null
  where t.items > 0 group by t.group_id
)
select m.group_id, m.user_id,
       coalesce(t.items, 0) as items,
       case
         when coalesce(t.items, 0) = 0 or p.n is null then 0
         when m.user_id = g.host_id then
           greatest(coalesce(g.ongkir, 0) - coalesce(g.discount, 0), 0)
           - (p.n - 1) * (greatest(coalesce(g.ongkir, 0) - coalesce(g.discount, 0), 0) / p.n)
         else greatest(coalesce(g.ongkir, 0) - coalesce(g.discount, 0), 0) / p.n
       end as delivery_share,
       m.bill_total,
       m.proof_at, m.paid_at
from public.members m
join public.groups g on g.id = m.group_id
left join item_totals t on t.group_id = m.group_id and t.user_id = m.user_id
left join payers p on p.group_id = m.group_id
where m.removed_at is null;

create function public.group_subtotal(g uuid) returns int language sql stable security definer set search_path = '' as $$
  select coalesce(sum(unit_price * qty), 0)::int from public.items where group_id = g
$$;
revoke execute on function public.group_subtotal(uuid) from public, anon;
grant execute on function public.group_subtotal(uuid) to authenticated;

-- ---------------------------------------------------------------- notifications

create function public.rp(n int) returns text language sql immutable as $$
  select 'Rp ' || replace(to_char(n, 'FM999,999,999'), ',', '.')
$$;

create function public.notify(u uuid, g uuid, k text, t text, b text) returns void
language sql security definer set search_path = '' as $$
  insert into public.notifications (user_id, group_id, kind, title, body) values (u, g, k, t, b)
$$;

-- Everyone in the group except `skip`.
create function public.notify_group(g uuid, skip uuid, k text, t text, b text) returns void
language sql security definer set search_path = '' as $$
  insert into public.notifications (user_id, group_id, kind, title, body)
  select m.user_id, g, k, t, b from public.members m
  where m.group_id = g and m.removed_at is null and m.user_id is distinct from skip
$$;
revoke execute on function public.notify(uuid, uuid, text, text, text), public.notify_group(uuid, uuid, text, text, text)
  from public, anon, authenticated;

create function public.display_name(u uuid) returns text language sql stable security definer set search_path = '' as $$
  select coalesce(nullif(name, ''), 'Someone') from public.profiles where id = u
$$;
revoke execute on function public.display_name(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- guards

create function public.require_host(g uuid, states text[]) returns public.groups
language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  select * into r from public.groups where id = g for update;
  if r.id is null or r.host_id <> (select auth.uid()) then raise exception 'only the host can do this'; end if;
  if not (r.state = any (states)) then raise exception 'not possible while the group is %', r.state; end if;
  return r;
end $$;
revoke execute on function public.require_host(uuid, text[]) from public, anon, authenticated;

-- ---------------------------------------------------------------- joining and leaving

create function public.group_preview(code text) returns table (
  id uuid, name text, host_name text, area text, delivery_at timestamptz, cutoff_at timestamptz,
  state text, members int, already_member boolean)
language sql stable security definer set search_path = '' as $$
  select g.id, g.name, public.display_name(g.host_id), g.area, g.delivery_at, g.cutoff_at, g.state,
         (select count(*)::int from public.members m where m.group_id = g.id and m.removed_at is null),
         exists (select 1 from public.members m where m.group_id = g.id and m.user_id = (select auth.uid()) and m.removed_at is null)
  from public.groups g where g.code = upper(group_preview.code) and not g.personal
$$;

create function public.join_group(code text) returns uuid language plpgsql security definer set search_path = '' as $$
declare g public.groups; me uuid := (select auth.uid());
begin
  select * into g from public.groups where groups.code = upper(join_group.code) and not personal;
  if g.id is null then raise exception 'This group link is not valid'; end if;
  if g.state <> 'open' then raise exception 'This group is no longer taking orders'; end if;
  insert into public.members (group_id, user_id) values (g.id, me)
    on conflict (group_id, user_id) do update set removed_at = null, joined_at = now()
    where members.removed_at is not null;
  if found then
    perform public.notify(g.host_id, g.id, 'joined', g.name, public.display_name(me) || ' joined your group.');
  end if;
  return g.id;
end $$;

create function public.leave_group(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; me uuid := (select auth.uid());
begin
  select * into r from public.groups where id = g;
  if r.host_id = me then raise exception 'The host can cancel the group instead'; end if;
  if r.state <> 'open' then raise exception 'You can only leave while the group is open'; end if;
  delete from public.items where group_id = g and owner_id = me;
  update public.members set removed_at = now() where group_id = g and user_id = me;
end $$;

create function public.remove_member(g uuid, u uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  r := public.require_host(g, array['open', 'locked', 'edits']);
  if u = r.host_id then raise exception 'The host cannot remove themselves'; end if;
  delete from public.items where group_id = g and owner_id = u;
  update public.members set removed_at = now() where group_id = g and user_id = u and removed_at is null;
  perform public.notify(u, g, 'removed', r.name, 'The host removed you from this group.');
end $$;

-- ---------------------------------------------------------------- locking and edit rounds

create function public.lock_body(r public.groups) returns text language sql immutable as $$
  select case when r.pay_rule = 'pay_first'
    then 'Orders are in. Pay the host once the bill is final so they can order.'
    else 'Orders are in. The host is checking everything before sending it to Atas.' end
$$;

create function public.lock_group(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  r := public.require_host(g, array['open', 'edits']);
  if exists (select 1 from public.items where group_id = g and flagged_at is not null) then
    raise exception 'Some requested edits are not done yet';
  end if;
  update public.groups set state = 'locked', locked_at = now() where id = g;
  perform public.notify_group(g, r.host_id, 'locked', r.name || ' is locked', public.lock_body(r));
end $$;

create function public.unlock_group(g uuid, new_cutoff timestamptz default null) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  r := public.require_host(g, array['locked']);
  update public.groups set state = 'open', cutoff_at = new_cutoff, cutoff_reminded = false where id = g;
  perform public.notify_group(g, r.host_id, 'unlocked', r.name || ' is open again', 'You can add or change items.');
end $$;

create function public.request_edit(item uuid, reason text) returns void language plpgsql security definer set search_path = '' as $$
declare i public.items; r public.groups;
begin
  select * into i from public.items where id = item;
  if i.id is null then raise exception 'unknown item'; end if;
  r := public.require_host(i.group_id, array['locked', 'edits']);
  update public.items set flag_reason = left(coalesce(reason, ''), 140), flagged_at = now() where id = item;
  update public.groups set state = 'edits' where id = i.group_id;
  update public.members set done_editing_at = null where group_id = i.group_id and user_id = i.owner_id;
  perform public.notify(i.owner_id, i.group_id, 'edit_requested', 'Please change an item',
    i.name || ': ' || coalesce(nullif(reason, ''), 'the host asked you to change it.'));
end $$;

create function public.done_editing(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; me uuid := (select auth.uid());
begin
  select * into r from public.groups where id = g;
  if not public.is_member(g) or r.state <> 'edits' then raise exception 'nothing to finish'; end if;
  update public.items set flag_reason = null, flagged_at = null where group_id = g and owner_id = me;
  update public.members set done_editing_at = now() where group_id = g and user_id = me;
  perform public.notify(r.host_id, g, 'edit_done', r.name, public.display_name(me) || ' finished editing.');
end $$;

-- ---------------------------------------------------------------- Atas

create function public.mark_sent(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  r := public.require_host(g, array['locked']);
  update public.groups set state = 'sent', sent_at = now() where id = g;
  perform public.notify_group(g, r.host_id, 'sent', 'Order sent to Atas', r.name || ': waiting for Atas to confirm.');
end $$;

create function public.confirm_atas(g uuid, ongkir int, discount int) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.groups; b record;
begin
  r := public.require_host(g, array['sent']);
  if ongkir < 0 or discount < 0 then raise exception 'amounts cannot be negative'; end if;
  update public.groups set state = 'confirmed', confirmed_at = now(),
    ongkir = confirm_atas.ongkir, discount = confirm_atas.discount where id = g;
  for b in select * from public.group_bill_v v where v.group_id = g loop
    update public.members set bill_total = b.items + b.delivery_share,
      paid_at = case when b.user_id = r.host_id or b.items + b.delivery_share = 0 then now() end
    where group_id = g and user_id = b.user_id;
    if b.user_id <> r.host_id and b.items + b.delivery_share > 0 then
      perform public.notify(b.user_id, g, 'bill_final',
        'Atas confirmed: your bill is ' || public.rp(b.items + b.delivery_share),
        case when r.pay_rule = 'pay_first' then 'Pay the host now so they can finish the order.'
             else 'The order is in. Pay the host when you can.' end);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------- payments

create function public.claim_paid(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; me uuid := (select auth.uid()); m public.members;
begin
  select * into r from public.groups where id = g;
  select * into m from public.members where group_id = g and user_id = me and removed_at is null;
  if m.user_id is null then raise exception 'not a member'; end if;
  if r.state not in ('confirmed', 'delivered') then raise exception 'The bill is not final yet'; end if;
  update public.members set proof_at = now() where group_id = g and user_id = me;
  perform public.notify(r.host_id, g, 'member_paid', r.name,
    public.display_name(me) || ' says they paid ' || public.rp(coalesce(m.bill_total, 0)) || '.');
end $$;

create function public.confirm_paid(g uuid, u uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  r := public.require_host(g, array['confirmed', 'delivered', 'closed']);
  update public.members set paid_at = now() where group_id = g and user_id = u and paid_at is null;
  if found then
    perform public.notify(u, g, 'payment_confirmed', r.name, 'The host confirmed your payment. Thanks!');
    if not exists (select 1 from public.members where group_id = g and removed_at is null and paid_at is null) then
      perform public.notify(r.host_id, g, 'everyone_paid', r.name, 'Everyone has paid.');
    end if;
  end if;
end $$;

create function public.nudge(g uuid, u uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; m public.members;
begin
  r := public.require_host(g, array['confirmed', 'delivered', 'closed']);
  select * into m from public.members where group_id = g and user_id = u;
  if m.paid_at is not null then return; end if;
  if m.nudged_at > now() - interval '1 hour' then raise exception 'You nudged them less than an hour ago'; end if;
  update public.members set nudged_at = now() where group_id = g and user_id = u;
  perform public.notify(u, g, 'nudge', 'Payment reminder',
    r.name || ': you owe the host ' || public.rp(coalesce(m.bill_total, 0)) || '.');
end $$;

-- ---------------------------------------------------------------- delivery and closing

create function public.confirm_delivered(g uuid, path text) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; me uuid := (select auth.uid());
begin
  select * into r from public.groups where id = g for update;
  if not public.is_member(g) then raise exception 'not a member'; end if;
  if r.state <> 'confirmed' then raise exception 'Not possible while the group is %', r.state; end if;
  if path !~ ('^' || g::text || '/[0-9a-f-]{36}\.jpg$') then raise exception 'bad photo path'; end if;
  insert into public.delivery_proofs (group_id, path, by_user) values (g, path, me);
  update public.groups set state = 'delivered', delivered_at = now() where id = g;
  perform public.notify_group(g, me, 'delivered', 'Delivered!', r.name || ': ' || public.display_name(me) || ' received the order.');
end $$;

create function public.report_photo(proof uuid) returns void language plpgsql security definer set search_path = '' as $$
declare p public.delivery_proofs;
begin
  select * into p from public.delivery_proofs where id = proof;
  if p.id is null or not public.is_member(p.group_id) then raise exception 'not found'; end if;
  update public.delivery_proofs set hidden = true, reported_by = (select auth.uid()) where id = proof;
end $$;

create function public.close_group(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  r := public.require_host(g, array['delivered']);
  update public.groups set state = 'closed', closed_at = now() where id = g;
  perform public.notify_group(g, r.host_id, 'closed', 'Order closed', r.name || ' is closed. See you next time!');
end $$;

create function public.cancel_group(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  r := public.require_host(g, array['open', 'locked', 'edits', 'sent']);
  update public.groups set state = 'cancelled', cancelled_at = now() where id = g;
  perform public.notify_group(g, r.host_id, 'cancelled', 'Group cancelled', r.name || ' was cancelled by the host.');
end $$;

-- ---------------------------------------------------------------- splits

-- shares: [{"user":"<uuid>","pct":50}, ...], including the owner, summing to 100.
create function public.propose_split(item uuid, shares jsonb) returns uuid language plpgsql security definer set search_path = '' as $$
declare i public.items; me uuid := (select auth.uid()); s uuid; total numeric; x jsonb;
begin
  select * into i from public.items where id = item;
  if i.id is null or not public.is_member(i.group_id) then raise exception 'not found'; end if;
  if not exists (select 1 from public.groups where id = i.group_id and state = 'open') then
    raise exception 'Splits can only be proposed while the group is open';
  end if;
  select sum((e->>'pct')::numeric) into total from jsonb_array_elements(shares) e;
  if total is distinct from 100 then raise exception 'Shares must add up to 100%%'; end if;
  if jsonb_array_length(shares) < 2 then raise exception 'A split needs at least two people'; end if;
  if not exists (select 1 from jsonb_array_elements(shares) e where (e->>'user')::uuid = i.owner_id) then
    raise exception 'The item owner must keep a share';
  end if;
  insert into public.splits (item_id, proposer_id, state)
    values (item, me, case when me = i.owner_id then 'accepted' else 'pending' end) returning id into s;
  for x in select * from jsonb_array_elements(shares) loop
    if not exists (select 1 from public.members where group_id = i.group_id and user_id = (x->>'user')::uuid and removed_at is null) then
      raise exception 'Everyone in a split must be in the group';
    end if;
    insert into public.split_shares (split_id, user_id, pct, accepted_at)
      values (s, (x->>'user')::uuid, (x->>'pct')::numeric,
              case when (x->>'user')::uuid in (me, i.owner_id) and me = i.owner_id then now()
                   when (x->>'user')::uuid = me then now() end);
  end loop;
  if me <> i.owner_id then
    perform public.notify(i.owner_id, i.group_id, 'split_proposed', 'Split request',
      public.display_name(me) || ' wants to split your ' || i.name || '.');
  else
    perform public.notify(x2.user_id, i.group_id, 'split_invited', 'Share an item?',
      public.display_name(me) || ' invited you to share ' || i.name || '.')
    from public.split_shares x2 where x2.split_id = s and x2.user_id <> me;
  end if;
  return s;
end $$;

-- The owner answers a split someone else proposed.
create function public.respond_split(split uuid, accept boolean) returns void language plpgsql security definer set search_path = '' as $$
declare sp public.splits; i public.items; me uuid := (select auth.uid());
begin
  select * into sp from public.splits where id = split and state = 'pending';
  select * into i from public.items where id = sp.item_id;
  if sp.id is null or i.owner_id <> me then raise exception 'not yours to answer'; end if;
  if accept then
    update public.splits set state = 'accepted' where id = split;
    update public.split_shares set accepted_at = now() where split_id = split and user_id in (me, sp.proposer_id);
    perform public.notify(x.user_id, i.group_id, 'split_invited', 'Share an item?',
      public.display_name(me) || ' is splitting ' || i.name || '. Accept your share.')
    from public.split_shares x where x.split_id = split and x.accepted_at is null;
  else
    update public.splits set state = 'declined' where id = split;
  end if;
  perform public.notify(sp.proposer_id, i.group_id, 'split_answered',
    case when accept then 'Split accepted' else 'Split declined' end,
    public.display_name(me) || case when accept then ' agreed to split ' else ' declined to split ' end || i.name || '.');
end $$;

-- An invitee accepts or declines their share.
create function public.answer_share(split uuid, accept boolean) returns void language plpgsql security definer set search_path = '' as $$
declare sp public.splits; i public.items; me uuid := (select auth.uid());
begin
  select * into sp from public.splits where id = split and state = 'accepted';
  select * into i from public.items where id = sp.item_id;
  if sp.id is null or not exists (select 1 from public.split_shares where split_id = split and user_id = me) then
    raise exception 'not part of this split';
  end if;
  if accept then
    update public.split_shares set accepted_at = now() where split_id = split and user_id = me;
  else
    update public.splits set state = 'declined' where id = split;
  end if;
  perform public.notify(u, i.group_id, 'split_answered',
    case when accept then 'Share accepted' else 'Share declined' end,
    public.display_name(me) || case when accept then ' accepted a share of ' else ' declined a share of ' end || i.name || '.')
  from unnest(array[i.owner_id, sp.proposer_id]) as u where u <> me group by u;
end $$;

-- Removing a split item cancels the split and tells everyone in it.
create function public.cancel_splits_of_item() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.notify(x.user_id, old.group_id, 'split_cancelled', 'Split cancelled',
    old.name || ' was removed, so the split is off.')
  from public.splits s join public.split_shares x on x.split_id = s.id
  where s.item_id = old.id and s.state in ('pending', 'accepted') and x.user_id <> old.owner_id;
  return old;
end $$;
create trigger cancel_splits_of_item before delete on public.items for each row execute function public.cancel_splits_of_item();

-- ---------------------------------------------------------------- automatic notices

-- Rp 200.000 reached: once per group.
create function public.check_discount() returns trigger language plpgsql security definer set search_path = '' as $$
declare g public.groups;
begin
  select * into g from public.groups where id = coalesce(new.group_id, old.group_id);
  if not g.discount_notified and not g.personal and public.group_subtotal(g.id) >= 200000 then
    update public.groups set discount_notified = true where id = g.id;
    perform public.notify_group(g.id, null, 'discount_unlocked', 'Rp 200.000 reached!',
      g.name || ': the ongkir discount is unlocked.');
  end if;
  return null;
end $$;
create trigger check_discount after insert or update or delete on public.items
  for each row execute function public.check_discount();

-- A product goes unavailable on the menu: tell whoever has it in a live order, once.
create function public.notify_sold_out() returns trigger language plpgsql security definer set search_path = '' as $$
declare i record;
begin
  if new.available or not old.available then return new; end if;
  for i in select it.id, it.owner_id, it.group_id, it.name, g.host_id from public.items it
           join public.groups g on g.id = it.group_id
           where it.product_id = new.id and not it.soldout_notified and g.state in ('open', 'locked', 'edits') loop
    update public.items set soldout_notified = true where id = i.id;
    perform public.notify(i.owner_id, i.group_id, 'sold_out', 'Sold out', i.name || ' is sold out on the Atas menu today.');
    if i.host_id <> i.owner_id then
      perform public.notify(i.host_id, i.group_id, 'sold_out', 'Sold out', i.name || ' in your group is sold out today.');
    end if;
  end loop;
  return new;
end $$;
create trigger notify_sold_out after update of available on public.products
  for each row execute function public.notify_sold_out();

-- Runs every minute (pg_cron): reminder 30 min before cutoff, auto-lock at cutoff.
create function public.tick() returns void language plpgsql security definer set search_path = '' as $$
declare g public.groups;
begin
  for g in select * from public.groups where state = 'open' and not cutoff_reminded
           and cutoff_at between now() and now() + interval '30 minutes' loop
    update public.groups set cutoff_reminded = true where id = g.id;
    perform public.notify_group(g.id, null, 'cutoff_soon', 'Cutoff in 30 minutes', g.name || ': add your items before it locks.');
  end loop;
  for g in select * from public.groups where state = 'open' and cutoff_at <= now() loop
    update public.groups set state = 'locked', locked_at = now() where id = g.id;
    perform public.notify_group(g.id, null, 'locked', g.name || ' is locked', public.lock_body(g));
  end loop;
end $$;

-- ---------------------------------------------------------------- grants

revoke execute on function
  public.lock_body(public.groups), public.rp(int), public.tick(),
  public.check_discount(), public.notify_sold_out(), public.cancel_splits_of_item()
  from public, anon, authenticated;

revoke execute on function
  public.group_preview(text), public.join_group(text), public.leave_group(uuid), public.remove_member(uuid, uuid),
  public.lock_group(uuid), public.unlock_group(uuid, timestamptz), public.request_edit(uuid, text), public.done_editing(uuid),
  public.mark_sent(uuid), public.confirm_atas(uuid, int, int), public.claim_paid(uuid), public.confirm_paid(uuid, uuid),
  public.nudge(uuid, uuid), public.confirm_delivered(uuid, text), public.report_photo(uuid), public.close_group(uuid),
  public.cancel_group(uuid), public.propose_split(uuid, jsonb), public.respond_split(uuid, boolean), public.answer_share(uuid, boolean)
  from public, anon;
grant execute on function
  public.group_preview(text), public.join_group(text), public.leave_group(uuid), public.remove_member(uuid, uuid),
  public.lock_group(uuid), public.unlock_group(uuid, timestamptz), public.request_edit(uuid, text), public.done_editing(uuid),
  public.mark_sent(uuid), public.confirm_atas(uuid, int, int), public.claim_paid(uuid), public.confirm_paid(uuid, uuid),
  public.nudge(uuid, uuid), public.confirm_delivered(uuid, text), public.report_photo(uuid), public.close_group(uuid),
  public.cancel_group(uuid), public.propose_split(uuid, jsonb), public.respond_split(uuid, boolean), public.answer_share(uuid, boolean)
  to authenticated;
