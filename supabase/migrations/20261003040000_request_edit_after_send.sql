-- Atas can reply that an item is sold out after the order went out. The host may then flag it from 'sent' too:
-- the group goes back to 'edits', the owner swaps or removes it, the host locks again and re-sends.
create or replace function public.request_edit(item uuid, reason text) returns void language plpgsql security definer set search_path = '' as $$
declare i public.items; r public.groups;
begin
  select * into i from public.items where id = item;
  if i.id is null then raise exception 'unknown item'; end if;
  r := public.require_host(i.group_id, array['locked', 'edits', 'sent']);
  if r.pay_rule = 'pay_first' and r.bill_final_at is not null then perform public.unfreeze_bills(i.group_id); end if;
  update public.items set flag_reason = left(coalesce(reason, ''), 140), flagged_at = now() where id = item;
  update public.groups set state = 'edits' where id = i.group_id;
  update public.members set done_editing_at = null where group_id = i.group_id and user_id = i.owner_id;
  perform public.notify(i.owner_id, i.group_id, 'edit_requested', public.display_name(r.host_id) || ' asked you to edit an item',
    i.name || ': ' || coalesce('“' || nullif(left(reason, 140), '') || '”', 'please swap or remove it.'));
end $$;
