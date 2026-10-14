-- Sign in with Apple and the hosting gate, as the real roles. Rolls back; run after the migration:
--   BEGIN; \i supabase/migrations/20261014100000_sign_in_with_apple.sql; \i supabase/tests/apple.sql
--   (this file's own BEGIN warns inside that transaction; its ROLLBACK undoes the migration too.)
-- Putri signed in with Apple and has no number yet; Rani verified hers.
--   Putri can't create a group or a personal order; Rani can.
--   apple_linked() is false until the account has an Apple ID, then true; anon can't call it.
--   Clients can't read apple_accounts. A number is optional but keeps its format and stays unique.
begin;

create temp table t_ids (k text primary key, v uuid);
insert into t_ids values ('putri', gen_random_uuid()), ('rani', gen_random_uuid());
grant select on t_ids to authenticated;
create function pg_temp.id(k text) returns uuid language sql as $$ select v from t_ids where t_ids.k = id.k $$;
create function pg_temp.act(k text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.id(k), 'role', 'authenticated')::text, true)
$$;
-- Run a statement as a user; it must succeed.
create function pg_temp.run(k text, q text) returns void language plpgsql as $$
begin
  perform pg_temp.act(k);
  set local role authenticated;
  execute q;
  reset role;
end $$;
-- Run a statement as a user (or anon when k is null); it must fail with an error like `want`.
create function pg_temp.fails(k text, q text, want text) returns void language plpgsql as $$
declare got text;
begin
  if k is null then perform set_config('request.jwt.claims', '{"role":"anon"}', true); else perform pg_temp.act(k); end if;
  begin
    if k is null then set local role anon; else set local role authenticated; end if;
    execute q;
    got := null;
  exception when others then got := sqlerrm;
  end;
  reset role;
  if got is null then raise exception 'expected an error from: %', q; end if;
  if got not like want then raise exception 'wrong error from %: %', q, got; end if;
end $$;
-- A value as a user sees it.
create function pg_temp.linked(k text) returns boolean language plpgsql as $$
declare r boolean;
begin
  perform pg_temp.act(k);
  set local role authenticated;
  r := public.apple_linked();
  reset role;
  return r;
end $$;

insert into auth.users (id, email, aud, role) select v, k || '@test.invalid', 'authenticated', 'authenticated' from t_ids;
insert into public.profiles (id, phone, name) values (pg_temp.id('putri'), null, 'Putri'), (pg_temp.id('rani'), '6281277882210', 'Rani');

-- ---------------------------------------------------------------- hosting gate

select pg_temp.fails('putri', $q$insert into public.groups (name, area, delivery_at, cutoff_at) values ('Putri group', 'Kuta', now() + interval '1 day', now() + interval '3 hours')$q$,
                     'new row violates row-level security policy%');
select pg_temp.fails('putri', $q$insert into public.groups (name, personal, area, delivery_at) values ('My order', true, 'Kuta', now() + interval '1 day')$q$,
                     'new row violates row-level security policy%');
select pg_temp.run('rani', $q$insert into public.groups (name, area, delivery_at, cutoff_at) values ('Rani group', 'Kuta', now() + interval '1 day', now() + interval '3 hours')$q$);
select pg_temp.run('rani', $q$insert into public.groups (name, personal, area, delivery_at) values ('My order', true, 'Kuta', now() + interval '1 day')$q$);
-- Unverified people still join and order.
select pg_temp.run('putri', format('select public.join_group(%L)', (select code from public.groups where name = 'Rani group' and host_id = pg_temp.id('rani'))));
do $$ begin
  assert (select count(*) from public.groups where host_id = pg_temp.id('rani')) = 2, 'rani hosts both';
  assert (select count(*) from public.groups where host_id = pg_temp.id('putri')) = 0, 'putri hosts nothing';
  assert exists (select 1 from public.members m join public.groups g on g.id = m.group_id
                 where g.name = 'Rani group' and m.user_id = pg_temp.id('putri')), 'putri joined';
end $$;
-- Verifying opens the gate.
update public.profiles set phone = '6281290345521' where id = pg_temp.id('putri');
select pg_temp.run('putri', $q$insert into public.groups (name, area, delivery_at, cutoff_at) values ('Putri group', 'Kuta', now() + interval '1 day', now() + interval '3 hours')$q$);
update public.profiles set phone = null where id = pg_temp.id('putri');

-- ---------------------------------------------------------------- apple_linked, apple_accounts

do $$ begin
  assert not pg_temp.linked('rani'), 'rani not linked yet';
end $$;
insert into public.apple_accounts (user_id, sub, refresh_token) values (pg_temp.id('rani'), '001234.test.rani', 'r-token');
do $$ begin
  assert pg_temp.linked('rani'), 'rani linked';
  assert not pg_temp.linked('putri'), 'putri not linked';
end $$;
select pg_temp.fails(null, 'select public.apple_linked()', 'permission denied for function apple_linked');
select pg_temp.fails('rani', 'select * from public.apple_accounts', 'permission denied for table apple_accounts');
select pg_temp.fails('rani', $q$insert into public.apple_accounts (user_id, sub) values (auth.uid(), 'x')$q$, 'permission denied for table apple_accounts');

-- ---------------------------------------------------------------- numbers and codes

do $$
declare err text;
begin
  begin
    update public.profiles set phone = '12ab' where id = pg_temp.id('putri');
  exception when check_violation then err := 'check';
  end;
  assert err = 'check', 'phone format still checked';
  err := null;
  begin
    update public.profiles set phone = '6281277882210' where id = pg_temp.id('putri');
  exception when unique_violation then err := 'unique';
  end;
  assert err = 'unique', 'one number, one account';
end $$;
-- A verify-mode code belongs to its user and goes with the account.
insert into public.wa_codes (code, nonce, user_id) values ('TST1', 'nonce-test-1', pg_temp.id('putri'));
delete from auth.users where id = pg_temp.id('putri');
do $$ begin
  assert not exists (select 1 from public.wa_codes where code = 'TST1'), 'code deleted with the account';
  assert not exists (select 1 from public.profiles where id = pg_temp.id('putri')), 'profile deleted with the account';
end $$;
delete from auth.users where id = pg_temp.id('rani');
do $$ begin
  assert not exists (select 1 from public.apple_accounts where sub = '001234.test.rani'), 'apple row deleted with the account';
end $$;

select 'apple.sql: all assertions passed' as result;
rollback;
