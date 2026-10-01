-- 2-6 join preview: what the board shows before joining (pay rule, the basket so far, the host's picture and the
-- place; the host's WhatsApp for "Message Rani" on a locked group). Return type changes, so drop and recreate.
drop function public.group_preview(text);
create function public.group_preview(code text) returns table (
  id uuid, name text, host_name text, area text, delivery_at timestamptz, cutoff_at timestamptz,
  state text, members int, already_member boolean, pay_rule text, address_label text, subtotal int,
  host_phone text, host_avatar text, host_avatar_bg text)
language sql stable security definer set search_path = '' as $$
  select g.id, g.name, public.display_name(g.host_id), g.area, g.delivery_at, g.cutoff_at, g.state,
         (select count(*)::int from public.members m where m.group_id = g.id and m.removed_at is null),
         exists (select 1 from public.members m where m.group_id = g.id and m.user_id = (select auth.uid()) and m.removed_at is null),
         g.pay_rule, nullif(g.address_label, ''), public.group_subtotal(g.id),
         p.phone, p.avatar, p.avatar_bg
  from public.groups g join public.profiles p on p.id = g.host_id
  where g.code = upper(group_preview.code) and not g.personal
$$;
revoke execute on function public.group_preview(text) from public, anon;
grant execute on function public.group_preview(text) to authenticated;

-- 5-10 "Not received": the host rejects a "says paid" claim. Clears proof_at so the member can claim again, and
-- tells them.
create function public.reject_paid(g uuid, u uuid) returns void language plpgsql security definer set search_path = '' as $$
declare r public.groups; m public.members;
begin
  r := public.require_host(g, array['confirmed', 'delivered', 'closed']);
  update public.members set proof_at = null where group_id = g and user_id = u and paid_at is null and proof_at is not null
    returning * into m;
  if m.user_id is null then raise exception 'There is no payment claim to reject'; end if;
  perform public.notify(u, g, 'payment_not_received', public.display_name(r.host_id) || ' hasn’t received your payment yet',
    public.rp(coalesce(m.bill_total, 0)) || ' for ' || r.name || '. Check the transfer'
    || coalesce(' to ' || public.payout_label(r) || ' ' || public.payout_number(r), '') || ' and tap “I’ve paid” again.');
end $$;
revoke execute on function public.reject_paid(uuid, uuid) from public, anon;
grant execute on function public.reject_paid(uuid, uuid) to authenticated;
