-- tick() closes a group 3 days after delivery once everyone has paid (close_group's own rule), so it moves
-- to History without the host pressing Close. Hosts tend to stop opening a group once it is delivered.
-- A group with someone unpaid stays on Home, where the host can still nudge.

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
  for g in select * from public.groups r where r.state = 'delivered' and r.delivered_at <= now() - interval '3 days'
           and not exists (select 1 from public.members m where m.group_id = r.id and m.removed_at is null
                           and m.user_id <> r.host_id and coalesce(m.bill_total, 0) > 0 and m.paid_at is null) loop
    update public.groups set state = 'closed', closed_at = now() where id = g.id;
    perform public.notify_group(g.id, null, 'closed', g.name || ' is closed', 'Thanks for ordering together. Reorder anytime from History.');
  end loop;
  delete from public.wa_codes where created_at < now() - interval '1 day';
end $$;

revoke execute on function public.tick() from public, anon, authenticated;
