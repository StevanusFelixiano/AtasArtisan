-- Notification wording from the Claude Design "Notifications" board (#1–#22): names, amounts, WITA times and
-- the host's bank, instead of generic lines. Logic is unchanged; only the text each RPC writes.

create function public.wita_time(t timestamptz) returns text language sql immutable set search_path = '' as $$
  select to_char(t at time zone 'Asia/Makassar', 'HH24:MI')
$$;
create function public.wita_day(t timestamptz) returns text language sql immutable set search_path = '' as $$
  select to_char(t at time zone 'Asia/Makassar', 'Dy FMDD Mon, HH24:MI')
$$;
-- The bank or e-wallet label on the group's payout account, or null.
create function public.payout_label(r public.groups) returns text language sql stable security definer set search_path = '' as $$
  select nullif(a.label, '') from public.payout_accounts a where a.id = r.payout_account_id
$$;
create function public.payout_number(r public.groups) returns text language sql stable security definer set search_path = '' as $$
  select nullif(a.number, '') from public.payout_accounts a where a.id = r.payout_account_id
$$;

-- #3a / #3b: one notice per member; pay-first names each member's own items total.
create function public.notify_locked(r public.groups, skip uuid) returns void
language sql security definer set search_path = '' as $$
  insert into public.notifications (user_id, group_id, kind, title, body)
  select m.user_id, r.id, 'locked', r.name || ' is locked',
         case when r.pay_rule = 'pay_first'
           then 'Pay now so ' || public.display_name(r.host_id) || ' can order.'
                || case when coalesce(v.items, 0) > 0 then ' Your items come to ' || public.rp(v.items) || '.' else '' end
           else public.display_name(r.host_id) || ' is checking the order. The order is in — pay when you can, once the bill is final.'
         end
  from public.members m
  left join public.group_bill_v v on v.group_id = r.id and v.user_id = m.user_id
  where m.group_id = r.id and m.removed_at is null and m.user_id is distinct from skip
$$;

-- What a split looks like to its owner: "You 50%, Putri 25%, Kevin 25%".
create function public.split_people(s uuid, owner uuid) returns text language sql stable security definer set search_path = '' as $$
  select string_agg(case when x.user_id = owner then 'You' else public.display_name(x.user_id) end || ' ' || trim_scale(x.pct)::text || '%',
                    ', ' order by (x.user_id = owner) desc, x.pct desc)
  from public.split_shares x where x.split_id = s
$$;

-- #10a / #10b to the item owner and the proposer, except the person answering.
create function public.notify_split_answer(sp public.splits, i public.items, me uuid, accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare n int; waiting int;
begin
  select count(*), count(*) filter (where accepted_at is null) into n, waiting from public.split_shares where split_id = sp.id;
  insert into public.notifications (user_id, group_id, kind, title, body)
  select u, i.group_id, 'split_answered',
         case when accept then public.display_name(me) || ' accepted the ' || i.name || ' split'
              else public.display_name(me) || ' declined the split' end,
         case when not accept then i.name || ' stays whole on ' || public.display_name(i.owner_id) || '’s order.'
              when waiting = 0 then 'All ' || n || ' are in. ' || i.name || ' is split ' || n || ' ways under ' || public.display_name(i.owner_id) || '.'
              else 'Waiting on ' || waiting || ' more.' end
  from (select distinct unnest(array[i.owner_id, sp.proposer_id]) as u) people
  where u <> me;
end $$;

revoke execute on function public.wita_time(timestamptz), public.wita_day(timestamptz), public.payout_label(public.groups),
  public.payout_number(public.groups), public.notify_locked(public.groups, uuid), public.split_people(uuid, uuid),
  public.notify_split_answer(public.splits, public.items, uuid, boolean)
  from public, anon, authenticated;

-- #1
create or replace function public.join_group(code text) returns uuid language plpgsql security definer set search_path = '' as $$
declare g public.groups; me uuid := (select auth.uid());
begin
  select * into g from public.groups where groups.code = upper(join_group.code) and not personal;
  if g.id is null then raise exception 'This group link is not valid'; end if;
  if g.state <> 'open' then raise exception 'This group is no longer taking orders'; end if;
  insert into public.members (group_id, user_id) values (g.id, me)
    on conflict (group_id, user_id) do update set removed_at = null, joined_at = now()
    where members.removed_at is not null;
  if found then
    perform public.notify(g.host_id, g.id, 'joined', public.display_name(me) || ' joined ' || g.name,
      (select count(*) from public.members m where m.group_id = g.id and m.removed_at is null) || ' members now · '
      || public.rp(public.group_subtotal(g.id)) || ' of Rp 200.000.');
  end if;
  return g.id;
end $$;

-- #20
create or replace function public.remove_member(g uuid, u uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; what text;
begin
  r := public.require_host(g, array['open', 'locked', 'edits']);
  if u = r.host_id then raise exception 'The host cannot remove themselves'; end if;
  select string_agg(i.qty || '× ' || i.name, ', ' order by i.name) into what from public.items i where i.group_id = g and i.owner_id = u;
  delete from public.items where group_id = g and owner_id = u;
  update public.members set removed_at = now() where group_id = g and user_id = u and removed_at is null;
  perform public.notify(u, g, 'removed', 'You were removed from ' || r.name,
    public.display_name(r.host_id) || ' removed you'
    || case when what is null then '.' else ', so your items are out of the order: ' || what || '.' end);
end $$;

-- #3
create or replace function public.lock_group(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  r := public.require_host(g, array['open', 'edits']);
  if exists (select 1 from public.items where group_id = g and flagged_at is not null) then
    raise exception 'Some requested edits are not done yet';
  end if;
  update public.groups set state = 'locked', locked_at = now() where id = g;
  perform public.notify_locked(r, r.host_id);
end $$;

-- #4
create or replace function public.unlock_group(g uuid, new_cutoff timestamptz default null) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  r := public.require_host(g, array['locked']);
  update public.groups set state = 'open', cutoff_at = new_cutoff, cutoff_reminded = false where id = g;
  perform public.notify_group(g, r.host_id, 'unlocked', public.display_name(r.host_id) || ' unlocked ' || r.name,
    case when new_cutoff is null then 'Add or change items until it locks again.'
         else 'New cutoff ' || public.wita_time(new_cutoff) || '. Add or change items until then.' end);
end $$;

-- #5
create or replace function public.request_edit(item uuid, reason text) returns void language plpgsql security definer set search_path = '' as $$
declare i public.items; r public.groups;
begin
  select * into i from public.items where id = item;
  if i.id is null then raise exception 'unknown item'; end if;
  r := public.require_host(i.group_id, array['locked', 'edits']);
  update public.items set flag_reason = left(coalesce(reason, ''), 140), flagged_at = now() where id = item;
  update public.groups set state = 'edits' where id = i.group_id;
  update public.members set done_editing_at = null where group_id = i.group_id and user_id = i.owner_id;
  perform public.notify(i.owner_id, i.group_id, 'edit_requested', public.display_name(r.host_id) || ' asked you to edit an item',
    i.name || ': ' || coalesce('“' || nullif(left(reason, 140), '') || '”', 'please swap or remove it.'));
end $$;

-- #6
create or replace function public.done_editing(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; me uuid := (select auth.uid()); open_edits int;
begin
  select * into r from public.groups where id = g;
  if not public.is_member(g) or r.state <> 'edits' then raise exception 'nothing to finish'; end if;
  update public.items set flag_reason = null, flagged_at = null where group_id = g and owner_id = me;
  update public.members set done_editing_at = now() where group_id = g and user_id = me;
  select count(*) into open_edits from public.items where group_id = g and flagged_at is not null;
  perform public.notify(r.host_id, g, 'edit_done', public.display_name(me) || ' finished editing',
    case when open_edits = 0 then 'Every edit is done. Lock ' || r.name || ' again to send it.'
         else open_edits || case when open_edits = 1 then ' edit is' else ' edits are' end || ' still open in ' || r.name || '.' end);
end $$;

-- #13
create or replace function public.mark_sent(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  r := public.require_host(g, array['locked']);
  update public.groups set state = 'sent', sent_at = now() where id = g;
  perform public.notify_group(g, r.host_id, 'sent', 'Order sent to Atas',
    public.display_name(r.host_id) || ' sent ' || r.name || ' to Atas Artisan. Delivery ' || public.wita_day(r.delivery_at) || ' WITA.');
end $$;

-- #14a / #14b
create or replace function public.confirm_atas(g uuid, ongkir int, discount int) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.groups; b record; host text; bank text;
begin
  r := public.require_host(g, array['sent']);
  if ongkir < 0 or discount < 0 then raise exception 'amounts cannot be negative'; end if;
  update public.groups set state = 'confirmed', confirmed_at = now(),
    ongkir = confirm_atas.ongkir, discount = confirm_atas.discount where id = g;
  host := public.display_name(r.host_id);
  bank := public.payout_label(r);
  for b in select * from public.group_bill_v v where v.group_id = g loop
    update public.members set bill_total = b.items + b.delivery_share,
      paid_at = case when b.user_id = r.host_id or b.items + b.delivery_share = 0 then now() end
    where group_id = g and user_id = b.user_id;
    if b.user_id <> r.host_id and b.items + b.delivery_share > 0 then
      perform public.notify(b.user_id, g, 'bill_final',
        'Atas confirmed — your bill is final: ' || public.rp(b.items + b.delivery_share),
        case when r.pay_rule = 'pay_first' then 'Pay now so ' || host || ' can order.'
             else 'The order is in — pay when you can.' || coalesce(' Transfer to ' || host || ', ' || bank || '.', '') end);
    end if;
  end loop;
end $$;

-- #15
create or replace function public.claim_paid(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; me uuid := (select auth.uid()); m public.members; receipt boolean;
begin
  select * into r from public.groups where id = g;
  select * into m from public.members where group_id = g and user_id = me and removed_at is null;
  if m.user_id is null then raise exception 'not a member'; end if;
  if r.state not in ('confirmed', 'delivered') then raise exception 'The bill is not final yet'; end if;
  update public.members set proof_at = now() where group_id = g and user_id = me;
  receipt := exists (select 1 from storage.objects o where o.bucket_id = 'receipts' and o.name = g::text || '/' || me::text || '.jpg');
  perform public.notify(r.host_id, g, 'member_paid',
    public.display_name(me) || ' says they’ve paid ' || public.rp(coalesce(m.bill_total, 0)),
    case when receipt then 'Receipt attached. ' else '' end || 'Check ' || coalesce(public.payout_label(r), 'your account') || ' and mark it paid.');
end $$;

-- #16 and #18
create or replace function public.confirm_paid(g uuid, u uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; amount int;
begin
  r := public.require_host(g, array['confirmed', 'delivered', 'closed']);
  update public.members set paid_at = now() where group_id = g and user_id = u and paid_at is null returning bill_total into amount;
  if found then
    perform public.notify(u, g, 'payment_confirmed', public.display_name(r.host_id) || ' confirmed your payment',
      public.rp(coalesce(amount, 0)) || ' received. You’re all set for ' || to_char(r.delivery_at at time zone 'Asia/Makassar', 'FMDay') || '.');
    if not exists (select 1 from public.members where group_id = g and removed_at is null and paid_at is null) then
      perform public.notify(r.host_id, g, 'everyone_paid', 'Everyone has paid',
        public.rp((select coalesce(sum(bill_total), 0) from public.members where group_id = g and removed_at is null and user_id <> r.host_id))
        || ' collected for ' || r.name || '.');
    end if;
  end if;
end $$;

-- #17
create or replace function public.nudge(g uuid, u uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; m public.members;
begin
  r := public.require_host(g, array['confirmed', 'delivered', 'closed']);
  select * into m from public.members where group_id = g and user_id = u;
  if m.paid_at is not null then return; end if;
  if m.nudged_at > now() - interval '1 hour' then raise exception 'You nudged them less than an hour ago'; end if;
  update public.members set nudged_at = now() where group_id = g and user_id = u;
  perform public.notify(u, g, 'nudge', 'Reminder from ' || public.display_name(r.host_id) || ': ' || public.rp(coalesce(m.bill_total, 0)),
    r.name || ' is waiting on your payment.' || coalesce(' ' || public.payout_label(r) || ' ' || public.payout_number(r) || '.', ''));
end $$;

-- #19
create or replace function public.confirm_delivered(g uuid, path text) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; me uuid := (select auth.uid());
begin
  select * into r from public.groups where id = g for update;
  if not public.is_member(g) then raise exception 'not a member'; end if;
  if r.state <> 'confirmed' then raise exception 'Not possible while the group is %', r.state; end if;
  if path !~ ('^' || g::text || '/[0-9a-f-]{36}\.jpg$') then raise exception 'bad photo path'; end if;
  insert into public.delivery_proofs (group_id, path, by_user) values (g, path, me);
  update public.groups set state = 'delivered', delivered_at = now() where id = g;
  perform public.notify_group(g, me, 'delivered', 'Your Atas order arrived',
    public.display_name(me) || ' confirmed delivery at ' || coalesce(nullif(r.address_label, ''), r.area) || ', ' || public.wita_time(now()) || '.');
end $$;

-- #22
create or replace function public.close_group(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  r := public.require_host(g, array['delivered']);
  update public.groups set state = 'closed', closed_at = now() where id = g;
  perform public.notify_group(g, r.host_id, 'closed', r.name || ' is closed', 'Thanks for ordering together. Reorder anytime from History.');
end $$;

-- #21
create or replace function public.cancel_group(g uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups;
begin
  r := public.require_host(g, array['open', 'locked', 'edits', 'sent']);
  update public.groups set state = 'cancelled', cancelled_at = now() where id = g;
  perform public.notify_group(g, r.host_id, 'cancelled', r.name || ' was cancelled',
    public.display_name(r.host_id) || ' cancelled the group.' || case when r.state = 'sent' then '' else ' Nothing was sent to Atas.' end);
end $$;

-- #8 and #9
create or replace function public.propose_split(item uuid, shares jsonb) returns uuid language plpgsql security definer set search_path = '' as $$
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
    perform public.notify(i.owner_id, i.group_id, 'split_proposed', public.display_name(me) || ' wants to split your ' || i.name,
      public.split_people(s, i.owner_id) || '. Accept or decline.');
  else
    perform public.notify(x2.user_id, i.group_id, 'split_invited', public.display_name(me) || ' invited you to share ' || i.name,
      'Your share: ' || trim_scale(x2.pct)::text || '% · ' || public.rp(round(i.unit_price * i.qty * x2.pct / 100)::bigint) || '.')
    from public.split_shares x2 where x2.split_id = s and x2.user_id <> me;
  end if;
  return s;
end $$;

-- #9 (after the owner accepts) and #10
create or replace function public.respond_split(split uuid, accept boolean) returns void language plpgsql security definer set search_path = '' as $$
declare sp public.splits; i public.items; me uuid := (select auth.uid());
begin
  select * into sp from public.splits where id = split and state = 'pending';
  select * into i from public.items where id = sp.item_id;
  if sp.id is null or i.owner_id <> me then raise exception 'not yours to answer'; end if;
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

-- #10
create or replace function public.answer_share(split uuid, accept boolean) returns void language plpgsql security definer set search_path = '' as $$
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
  perform public.notify_split_answer(sp, i, me, accept);
end $$;

-- #11
create or replace function public.cancel_splits_of_item() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.notify(x.user_id, old.group_id, 'split_cancelled', old.name || ' split cancelled',
    old.name || ' was removed from the order, so your ' || public.rp(round(old.unit_price * old.qty * x.pct / 100)::bigint) || ' share is gone.')
  from public.splits s join public.split_shares x on x.split_id = s.id
  where s.item_id = old.id and s.state in ('pending', 'accepted') and x.user_id <> old.owner_id;
  return old;
end $$;

-- #12
create or replace function public.check_discount() returns trigger language plpgsql security definer set search_path = '' as $$
declare g public.groups; sub int;
begin
  select * into g from public.groups where id = coalesce(new.group_id, old.group_id);
  sub := public.group_subtotal(g.id);
  if not g.discount_notified and not g.personal and sub >= 200000 then
    update public.groups set discount_notified = true where id = g.id;
    perform public.notify_group(g.id, null, 'discount_unlocked', 'Discount unlocked!',
      g.name || ' hit ' || public.rp(sub) || '. The ongkir discount applies when ' || public.display_name(g.host_id) || ' sends the order.');
  end if;
  return null;
end $$;

-- #7
create or replace function public.notify_sold_out() returns trigger language plpgsql security definer set search_path = '' as $$
declare i record;
begin
  if new.available or not old.available then return new; end if;
  for i in select it.id, it.owner_id, it.group_id, it.name, g.host_id, g.name as gname from public.items it
           join public.groups g on g.id = it.group_id
           where it.product_id = new.id and not it.soldout_notified and g.state in ('open', 'locked', 'edits') loop
    update public.items set soldout_notified = true where id = i.id;
    perform public.notify(i.owner_id, i.group_id, 'sold_out', i.name || ' just sold out',
      'It’s in your ' || i.gname || ' order. Swap it before '
      || case when i.host_id = i.owner_id then 'you send' else public.display_name(i.host_id) || ' sends' end || ' the order.');
    if i.host_id <> i.owner_id then
      perform public.notify(i.host_id, i.group_id, 'sold_out', i.name || ' just sold out',
        public.display_name(i.owner_id) || ' has it in ' || i.gname || '. Ask them to swap it before you send the order.');
    end if;
  end loop;
  return new;
end $$;

-- #2 and the automatic #3
create or replace function public.tick() returns void language plpgsql security definer set search_path = '' as $$
declare g public.groups; sub int;
begin
  for g in select * from public.groups where state = 'open' and not cutoff_reminded
           and cutoff_at between now() and now() + interval '30 minutes' loop
    update public.groups set cutoff_reminded = true where id = g.id;
    sub := public.group_subtotal(g.id);
    perform public.notify_group(g.id, null, 'cutoff_soon', g.name || ' locks in 30 minutes',
      'Get your order in before ' || public.wita_time(g.cutoff_at) || '.'
      || case when sub < 200000 then ' ' || public.rp(200000 - sub) || ' to go for the ongkir discount.' else '' end);
  end loop;
  for g in select * from public.groups where state = 'open' and cutoff_at <= now() loop
    update public.groups set state = 'locked', locked_at = now() where id = g.id;
    perform public.notify_locked(g, null);
  end loop;
  delete from public.wa_codes where created_at < now() - interval '1 day';
end $$;

drop function public.lock_body(public.groups);
