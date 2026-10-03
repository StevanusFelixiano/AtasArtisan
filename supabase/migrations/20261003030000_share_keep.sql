-- The owner of a shared item always keeps at least one piece, and chooses how many (share_keep, 1 … pieces − 1).
-- Claims stop at share_pieces − share_keep, so other members can no longer claim the whole item. share_item
-- gains `keep` (default 1), so the three-argument call from builds 9–11 keeps working.
alter table public.items add column share_keep int;
update public.items set share_keep = 1 where share_pieces is not null;
alter table public.items add constraint share_keep_fits
  check (share_keep is null or share_pieces is null or share_keep between 1 and share_pieces - 1);

drop function public.share_item(uuid, int, int);
create function public.share_item(item uuid, pieces int, min_people int default null, keep int default 1) returns void
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
  if keep is null or keep < 1 or keep > pieces - 1 then
    raise exception 'Keep between 1 and % pieces for yourself', pieces - 1;
  end if;
  select coalesce(sum(c.pieces), 0) into claimed from public.item_claims c where c.item_id = item;
  if pieces - keep < claimed then
    raise exception '% already claimed, so you can keep at most %', public.piece_count(claimed), public.piece_count(pieces - claimed);
  end if;
  update public.items set share_pieces = share_item.pieces, share_min = min_people, share_keep = keep, qty = 1 where id = item;
  if i.share_pieces is null then
    perform public.notify_group(i.group_id, me, 'item_shared', public.display_name(me) || ' is sharing a ' || i.name,
      pieces || ' pieces, ' || public.rp(round(i.unit_price::numeric / pieces)::bigint) || ' each. Claim yours before '
      || coalesce(public.wita_time(r.cutoff_at), 'the order locks') || '.');
    -- Whoever asked for this item gets their pieces claimed for them, as far as they fit.
    left_ := pieces - keep - claimed;
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
  if others + pieces > i.share_pieces - coalesce(i.share_keep, 1) then
    raise exception 'Only % left', public.piece_count(i.share_pieces - coalesce(i.share_keep, 1) - others);
  end if;
  if pieces = 0 then
    delete from public.item_claims where item_id = item and user_id = me;
    return;
  end if;
  insert into public.item_claims (item_id, group_id, user_id, pieces) values (item, i.group_id, me, claim_pieces.pieces)
    on conflict (item_id, user_id) do update set pieces = excluded.pieces, updated_at = now();
  if pieces <> before then
    left_ := i.share_pieces - coalesce(i.share_keep, 1) - others - pieces;
    perform public.notify_quiet(i.owner_id, i.group_id, 'piece_claimed',
      public.display_name(me) || ' claimed ' || public.piece_count(pieces),
      'Of your ' || i.name || ' · ' || left_ || ' left');
  end if;
end $$;

revoke execute on function public.share_item(uuid, int, int, int) from public, anon;
grant execute on function public.share_item(uuid, int, int, int) to authenticated;
