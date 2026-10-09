-- Ready, auto-disengage, kick at lock and public groups, as the real roles. Rolls back; run with execute_sql or psql.
--
-- Group "r" (order first, private), host Rani: Dimas, Putri and Kevin order; Arief only claims pieces of Rani's
-- shared cake; Nadia orders nothing.
--   * Nadia can't tap Ready; everyone with a stake can, and the last of them sends the host one `all_ready`.
--   * Kevin changing his order clears only Kevin's Ready; a second "all ready" is sent once he is ready again.
--   * The host's own changes and service-role writes clear nobody.
--   * At lock Nadia is taken off the list with a `removed` notice; Arief (claim only) and the rest stay.
-- Group "t": the auto-lock in tick() kicks the same way.
-- Group "pub" (public, host Kevin) shows in public_groups() for outsiders only, and not after it locks.
begin;

create temp table t_ids (k text primary key, v uuid);
insert into t_ids values ('rani', gen_random_uuid()), ('dimas', gen_random_uuid()), ('putri', gen_random_uuid()),
  ('kevin', gen_random_uuid()), ('nadia', gen_random_uuid()), ('arief', gen_random_uuid());
create temp table t_g (k text primary key, v uuid, code text);
grant select on t_ids, t_g to authenticated;
create function pg_temp.id(k text) returns uuid language sql as $$ select v from t_ids where t_ids.k = id.k $$;
create function pg_temp.gid(k text) returns uuid language sql as $$ select v from t_g where t_g.k = gid.k $$;
create function pg_temp.act(k text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.id(k), 'role', 'authenticated')::text, true)
$$;
create function pg_temp.run(k text, q text) returns void language plpgsql as $$
begin
  perform pg_temp.act(k);
  set local role authenticated;
  execute q;
  reset role;
end $$;
create function pg_temp.fails(k text, q text, want text) returns void language plpgsql as $$
declare got text;
begin
  perform pg_temp.act(k);
  begin
    set local role authenticated;
    execute q;
    got := null;
  exception when others then got := sqlerrm;
  end;
  reset role;
  if got is null then raise exception 'expected an error from: %', q; end if;
  if got not like want then raise exception 'wrong error from %: %', q, got; end if;
end $$;
create function pg_temp.item(g text, p text) returns uuid language sql as $$
  select id from public.items where group_id = pg_temp.gid(g) and product_id = p
$$;
create function pg_temp.ready(g text, k text) returns boolean language sql as $$
  select ready_at is not null from public.members where group_id = pg_temp.gid(g) and user_id = pg_temp.id(k)
$$;
create function pg_temp.removed(g text, k text) returns boolean language sql as $$
  select removed_at is not null from public.members where group_id = pg_temp.gid(g) and user_id = pg_temp.id(k)
$$;
create function pg_temp.notes(g text, k text, kind text) returns int language sql as $$
  select count(*)::int from public.notifications where group_id = pg_temp.gid(g) and user_id = pg_temp.id(k) and notifications.kind = notes.kind
$$;
create function pg_temp.listed(viewer text, g text) returns boolean language plpgsql as $$
declare hit boolean;
begin
  perform pg_temp.act(viewer);
  set local role authenticated;
  select exists (select 1 from public.public_groups() p where p.id = pg_temp.gid(g)) into hit;
  reset role;
  return hit;
end $$;
create function pg_temp.mk(k text, host text, joiners text[], public_ boolean default false) returns void language plpgsql as $$
declare j text; g uuid;
begin
  perform pg_temp.act(host);
  set local role authenticated;
  insert into public.groups (name, area, delivery_at, cutoff_at, pay_rule, is_public)
    values ('Test ' || k, 'Kuta', now() + interval '1 day', now() + interval '3 hours', 'order_first', public_) returning id into g;
  reset role;
  insert into t_g select k, g, code from public.groups where id = g;
  foreach j in array joiners loop
    perform pg_temp.run(j, format('select public.join_group(%L)', (select code from t_g where t_g.k = mk.k)));
  end loop;
end $$;
create function pg_temp.add(g text, k text, p text, q int) returns void language plpgsql as $$
begin
  perform pg_temp.run(k, format('insert into public.items (group_id, product_id, qty) values (%L, %L, %s)', pg_temp.gid(g), p, q));
end $$;
create function pg_temp.ready_up(g text, k text) returns void language sql as $$
  select pg_temp.run(k, format('select public.set_ready(%L)', pg_temp.gid(g)))
$$;

insert into auth.users (id, email, aud, role) select v, k || '@test.invalid', 'authenticated', 'authenticated' from t_ids;
insert into public.profiles (id, phone, name) select v, '62812000000' || row_number() over (), initcap(k) from t_ids;
insert into public.products (id, name, base_price, option_groups, variants) values
  ('t-croissant', 'Butter Croissant', 12000, '[]', '[]'),
  ('t-cheesecake', 'Burnt Cheesecake 20 cm', 260000, '[]', '[]'),
  ('t-pain', 'Pain Au Chocolate', 16000, '[]', '[]'),
  ('t-brioche', 'Brioche Bun', 8000, '[]', '[]'),
  ('t-muffin', 'English Muffin', 5000, '[]', '[]');

-- ================================================================ ready

select pg_temp.mk('r', 'rani', array['dimas','putri','kevin','nadia','arief']);
select pg_temp.add('r', 'rani', 't-cheesecake', 1), pg_temp.add('r', 'dimas', 't-pain', 1),
       pg_temp.add('r', 'putri', 't-pain', 2), pg_temp.add('r', 'kevin', 't-brioche', 1);
select pg_temp.run('rani', format('select public.share_item(%L, 12, null)', pg_temp.item('r', 't-cheesecake')));
select pg_temp.run('arief', format('select public.claim_pieces(%L, 2)', pg_temp.item('r', 't-cheesecake')));

-- No stake, not a member, anon: refused.
select pg_temp.fails('nadia', format('select public.set_ready(%L)', pg_temp.gid('r')), 'Add something to your order first');
do $$
declare got text;
begin
  begin
    set local role anon;
    perform public.set_ready(pg_temp.gid('r'));
    got := null;
  exception when others then got := sqlerrm;
  end;
  reset role;
  assert got like 'permission denied%', 'anon cannot call set_ready: ' || coalesce(got, 'no error');
end $$;

select pg_temp.ready_up('r', 'dimas'), pg_temp.ready_up('r', 'putri'), pg_temp.ready_up('r', 'arief');
do $$ begin
  assert pg_temp.ready('r', 'dimas') and pg_temp.ready('r', 'putri') and pg_temp.ready('r', 'arief'), 'ready (a claim is a stake)';
  assert not pg_temp.ready('r', 'kevin'), 'kevin not yet';
  assert pg_temp.notes('r', 'rani', 'all_ready') = 0, 'not everyone yet';
end $$;
select pg_temp.ready_up('r', 'kevin');
select pg_temp.ready_up('r', 'dimas');  -- tapping again changes nothing
do $$ begin
  assert pg_temp.notes('r', 'rani', 'all_ready') = 1, 'host told once (host and Nadia not counted)';
  assert (select body from public.notifications where group_id = pg_temp.gid('r') and kind = 'all_ready')
         = 'Test r: all 4 people are ready. Lock the order when you want.', 'all_ready copy';
end $$;

-- Kevin changes his order: only Kevin is un-readied.
select pg_temp.run('kevin', format('update public.items set qty = 2 where id = %L', pg_temp.item('r', 't-brioche')));
do $$ begin
  assert not pg_temp.ready('r', 'kevin'), 'kevin un-readied by his own change';
  assert pg_temp.ready('r', 'dimas') and pg_temp.ready('r', 'putri') and pg_temp.ready('r', 'arief'), 'others untouched';
end $$;
-- Rani (host) changes the shared cake, which moves Arief's bill: Arief stays ready.
select pg_temp.run('rani', format('select public.share_item(%L, 12, null, 2)', pg_temp.item('r', 't-cheesecake')));
-- A service-role write (no auth.uid()) clears nobody.
select set_config('request.jwt.claims', '', true);
update public.items set note = 'svc' where id = pg_temp.item('r', 't-pain') and owner_id = pg_temp.id('putri');
do $$ begin
  assert pg_temp.ready('r', 'arief') and pg_temp.ready('r', 'putri'), 'host and service writes clear nobody';
end $$;
-- Arief edits his claim: un-readied. Kevin and Arief ready again → a second notice.
select pg_temp.run('arief', format('select public.claim_pieces(%L, 3)', pg_temp.item('r', 't-cheesecake')));
do $$ begin assert not pg_temp.ready('r', 'arief'), 'claim change un-readies'; end $$;
select pg_temp.ready_up('r', 'kevin'), pg_temp.ready_up('r', 'arief');
do $$ begin assert pg_temp.notes('r', 'rani', 'all_ready') = 2, 'told again after a change'; end $$;

-- ================================================================ public groups

select pg_temp.mk('pub', 'kevin', array['dimas'], true);
do $$ begin
  assert pg_temp.listed('putri', 'pub'), 'outsider sees the public group';
  assert not pg_temp.listed('dimas', 'pub') and not pg_temp.listed('kevin', 'pub'), 'members and host do not';
  assert not pg_temp.listed('putri', 'r'), 'private group hidden';
end $$;
-- Outsiders still can't read the group row directly.
do $$
declare n int;
begin
  perform pg_temp.act('putri');
  set local role authenticated;
  select count(*) into n from public.groups where id = pg_temp.gid('pub');
  reset role;
  assert n = 0, 'RLS still hides a public group row from non-members';
end $$;
select pg_temp.run('putri', format('select public.join_group(%L)', (select code from t_g where k = 'pub')));
do $$ begin assert not pg_temp.listed('putri', 'pub'), 'gone from the list once joined'; end $$;

-- ================================================================ kick at lock

select pg_temp.run('rani', format('select public.lock_group(%L)', pg_temp.gid('r')));
do $$ begin
  assert pg_temp.removed('r', 'nadia'), 'stake-less member removed at lock';
  assert pg_temp.notes('r', 'nadia', 'removed') = 1, 'and told';
  assert pg_temp.notes('r', 'nadia', 'locked') = 0, 'no lock notice for the removed member';
  assert not (pg_temp.removed('r', 'arief') or pg_temp.removed('r', 'dimas') or pg_temp.removed('r', 'putri')
              or pg_temp.removed('r', 'kevin') or pg_temp.removed('r', 'rani')), 'everyone with a stake stays';
end $$;
select pg_temp.fails('dimas', format('select public.set_ready(%L)', pg_temp.gid('r')), 'This order isn’t open any more');

-- tick() auto-lock kicks too.
select pg_temp.mk('t', 'dimas', array['nadia','putri']);
select pg_temp.add('t', 'putri', 't-muffin', 1);
update public.groups set cutoff_at = now() - interval '1 minute' where id = pg_temp.gid('t');
update public.groups set cutoff_at = now() - interval '1 minute' where id = pg_temp.gid('pub');
select public.tick();
do $$ begin
  assert (select state from public.groups where id = pg_temp.gid('t')) = 'locked', 'auto-locked';
  assert pg_temp.removed('t', 'nadia') and not pg_temp.removed('t', 'putri'), 'auto-lock kicks the stake-less only';
  assert not pg_temp.listed('nadia', 'pub'), 'locked public group leaves the list';
end $$;

select 'ready.sql: all assertions passed' as result;
rollback;
