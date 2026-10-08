-- Undoes 20261008100000_claim_settles_ask: Brent's ask was for a genuinely unshared second cheesecake, so a claim
-- on another copy is no reason to close it. claim_pieces as it was.
create or replace function public.claim_pieces(item uuid, pieces int) returns void language plpgsql security definer set search_path = '' as $$
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
