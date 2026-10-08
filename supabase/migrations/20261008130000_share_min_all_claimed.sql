-- A shared item's minimum of people is met once enough people joined, or once every claimable piece is claimed.
-- One person may claim several pieces, so a fully claimed item could fall short on people and came off the order
-- at lock, though it cost the owner nothing extra. The app's chip uses the same rule (Pieces.minMet).
-- Claimable = share_pieces − share_keep (at least 1), as in the app's GroupStore.kept.

create or replace function public.lock_now(g uuid, skip uuid)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare r public.groups; it record; c record; people int; owner_amt bigint;
begin
  select * into r from public.groups where id = g for update;
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

create or replace function public.tick()
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare g public.groups; sub int; it record; short int;
begin
  for g in select * from public.groups where state = 'open' and not cutoff_reminded
           and cutoff_at between now() and now() + interval '30 minutes' loop
    update public.groups set cutoff_reminded = true where id = g.id;
    sub := public.group_subtotal(g.id);
    perform public.notify_group(g.id, null, 'cutoff_soon', g.name || ' locks in 30 minutes',
      'Get your order in before ' || public.wita_time(g.cutoff_at) || '.'
      || case when sub < 200000 then ' ' || public.rp(200000 - sub) || ' more for free ongkir.' else '' end);
    for it in select i.*, (select count(*)::int from public.item_claims x where x.item_id = i.id) as joiners,
                     (select coalesce(sum(x.pieces), 0)::int from public.item_claims x where x.item_id = i.id) as claimed
              from public.items i where i.group_id = g.id and i.share_min is not null loop
      short := it.share_min - 1 - it.joiners;
      if short > 0 and it.claimed < it.share_pieces - greatest(1, coalesce(it.share_keep, 1)) then
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
end $function$;

