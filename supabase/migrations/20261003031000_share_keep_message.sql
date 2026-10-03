-- share_item: when the pieces drop below the claims, say how many pieces are needed instead of a negative keep.
create or replace function public.share_item(item uuid, pieces int, min_people int default null, keep int default 1) returns void
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
  if pieces < claimed + 1 then
    raise exception 'Pieces must be at least %: % claimed plus 1 for you', claimed + 1, claimed;
  end if;
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
