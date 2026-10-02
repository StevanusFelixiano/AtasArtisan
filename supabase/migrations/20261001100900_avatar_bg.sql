-- Profile picture background colour (design 6-5b): a palette key the app maps to a Brand colour; null = the
-- pastel assigned by join order.
alter table public.profiles add column avatar_bg text check (avatar_bg ~ '^[a-z0-9]{2,20}$');
grant update (avatar_bg) on public.profiles to authenticated;
