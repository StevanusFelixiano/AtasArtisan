-- A profile picture chosen from Ataste's own art (giraffe poses and painting parodies), never an upload.
alter table public.profiles add column avatar text check (avatar ~ '^(pose|paint)-[a-z0-9-]{2,30}$');
grant update (avatar) on public.profiles to authenticated;
