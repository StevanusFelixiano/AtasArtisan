-- The oldest build each channel may still run. An app below it shows only the "Update Ataste" screen.
-- `testflight` is raised by ops/release/testflight.sh once a build is live for external testers;
-- `appstore` is raised by hand when an App Store release goes out.
create table public.app_release (
  channel text primary key check (channel in ('testflight', 'appstore')),
  min_build int not null
);
alter table public.app_release enable row level security;
create policy "anyone reads" on public.app_release for select to anon, authenticated using (true);
revoke all on public.app_release from anon, authenticated;
grant select on public.app_release to anon, authenticated;

insert into public.app_release values ('testflight', 9), ('appstore', 0);
