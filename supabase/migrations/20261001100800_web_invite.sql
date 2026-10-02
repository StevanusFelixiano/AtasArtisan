-- The invite page for people without the app (web fallback, design 2-7) reads this with the publishable key.
-- Anyone holding the 6-character code already sees the same in the app's join preview; first names only.
create function public.web_invite(code text) returns table (
  name text, host_name text, place text, delivery_at timestamptz, cutoff_at timestamptz, state text,
  members text[], member_count int)
language sql stable security definer set search_path = '' as $$
  select g.name, split_part(public.display_name(g.host_id), ' ', 1),
         coalesce(nullif(g.address_label, ''), g.area), g.delivery_at, g.cutoff_at, g.state,
         array(select split_part(public.display_name(m.user_id), ' ', 1) from public.members m
               where m.group_id = g.id and m.removed_at is null order by m.joined_at limit 4),
         (select count(*)::int from public.members m where m.group_id = g.id and m.removed_at is null)
  from public.groups g where g.code = upper(web_invite.code) and not g.personal
$$;
revoke execute on function public.web_invite(text) from public;
grant execute on function public.web_invite(text) to anon, authenticated;
