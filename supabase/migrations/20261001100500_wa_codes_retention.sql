-- Verification codes carry a phone number: tick() deletes them after a day (privacy policy).
create or replace function public.tick() returns void language plpgsql security definer set search_path = '' as $$
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
  delete from public.wa_codes where created_at < now() - interval '1 day';
end $$;
revoke execute on function public.tick() from public, anon, authenticated;
