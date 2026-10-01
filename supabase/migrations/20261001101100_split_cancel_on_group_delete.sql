-- Deleting a group (or an account, which cascades to its groups) deletes its items; the split-cancelled notice
-- then pointed at a group that no longer exists and the whole delete failed on notifications_group_id_fkey.
-- Only an item removed on its own cancels a split with a notice; when the group itself goes, nobody is told.
create or replace function public.cancel_splits_of_item() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.groups where id = old.group_id) then return old; end if;
  perform public.notify(x.user_id, old.group_id, 'split_cancelled', old.name || ' split cancelled',
    old.name || ' was removed from the order, so your ' || public.rp(round(old.unit_price * old.qty * x.pct / 100)::bigint) || ' share is gone.')
  from public.splits s join public.split_shares x on x.split_id = s.id
  where s.item_id = old.id and s.state in ('pending', 'accepted') and x.user_id <> old.owner_id;
  return old;
end $$;
