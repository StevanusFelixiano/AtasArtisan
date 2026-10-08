-- Pickup (board 7): "I've taken mine", Undo, the host's pickup nudge and "Fridge is clear", end to end as the real
-- roles. Rolls back; run with execute_sql.
--
-- Rani hosts; she shares her Burnt Cheesecake 20 cm (Rp 260.000) in 12 slices: Putri claims 3, Kevin 3, Rani keeps 6.
-- Putri adds 2 Pain Au Chocolate, Kevin a Brioche Bun. Nadia joins and orders nothing, so she isn't counted: 3 people.
-- Checks: only Delivered, only people with food, Undo sends nothing, one nudge per member (nudged_at untouched),
-- one "Fridge is clear" to the host even after an undo and re-take, bills never move, Close is never blocked.
begin;

create temp table t_ids (k text primary key, v uuid);
insert into t_ids values ('rani', gen_random_uuid()), ('putri', gen_random_uuid()), ('kevin', gen_random_uuid()),
  ('nadia', gen_random_uuid()), ('stranger', gen_random_uuid());
create temp table t_g (k text primary key, v uuid, code text);
create temp table t_bills (user_id uuid primary key, total int);
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
create function pg_temp.notes(g text, k text, kind text) returns int language sql as $$
  select count(*)::int from public.notifications where group_id = pg_temp.gid(g) and user_id = pg_temp.id(k) and notifications.kind = notes.kind
$$;
create function pg_temp.taken(g text, k text) returns boolean language sql as $$
  select taken_at is not null from public.members where group_id = pg_temp.gid(g) and user_id = pg_temp.id(k)
$$;
create function pg_temp.mk(k text, host text, joiners text[]) returns void language plpgsql as $$
declare j text; g uuid;
begin
  perform pg_temp.act(host);
  set local role authenticated;
  insert into public.groups (name, area, delivery_at, cutoff_at, pay_rule)
    values ('Test ' || k, 'Kuta', now() + interval '1 day', now() + interval '3 hours', 'order_first') returning id into g;
  reset role;
  insert into t_g select k, g, code from public.groups where id = g;
  foreach j in array joiners loop
    perform pg_temp.run(j, format('select public.join_group(%L)', (select code from t_g where t_g.k = mk.k)));
  end loop;
end $$;
create function pg_temp.add(g text, k text, p text, q int) returns void language plpgsql as $$
begin
  perform pg_temp.act(k);
  set local role authenticated;
  insert into public.items (group_id, product_id, qty, options) values (pg_temp.gid(g), p, q, '{}');
  reset role;
end $$;
create function pg_temp.take(k text, taken boolean) returns void language sql as $$
  select pg_temp.run(k, format('select public.mark_taken(%L, %L)', pg_temp.gid('p'), taken))
$$;

insert into auth.users (id, email, aud, role) select v, k || '@test.invalid', 'authenticated', 'authenticated' from t_ids;
insert into public.profiles (id, phone, name) select v, '62813000000' || row_number() over (), initcap(k) from t_ids;
insert into public.products (id, name, base_price, option_groups, variants) values
  ('t-cheesecake', 'Burnt Cheesecake 20 cm', 260000, '[]', '[]'),
  ('t-pain', 'Pain Au Chocolate', 16000, '[]', '[]'),
  ('t-brioche', 'Brioche Bun', 8000, '[]', '[]');

select pg_temp.mk('p', 'rani', array['putri','kevin','nadia']);
select pg_temp.add('p', 'rani', 't-cheesecake', 1), pg_temp.add('p', 'putri', 't-pain', 2), pg_temp.add('p', 'kevin', 't-brioche', 1);
select pg_temp.run('rani', format('select public.share_item(%L, 12, null, 1)', pg_temp.item('p', 't-cheesecake')));
select pg_temp.run('putri', format('select public.claim_pieces(%L, 3)', pg_temp.item('p', 't-cheesecake')));
select pg_temp.run('kevin', format('select public.claim_pieces(%L, 3)', pg_temp.item('p', 't-cheesecake')));
select pg_temp.run('rani', format('select public.lock_group(%L)', pg_temp.gid('p')));
select pg_temp.run('rani', format('select public.mark_sent(%L)', pg_temp.gid('p')));
select pg_temp.run('rani', format('select public.confirm_atas(%L, null, null)', pg_temp.gid('p')));

-- Not before Delivered.
select pg_temp.fails('putri', format('select public.mark_taken(%L, true)', pg_temp.gid('p')), 'Pickup opens once the order is delivered');
select pg_temp.fails('rani', format('select public.pickup_nudge(%L, %L)', pg_temp.gid('p'), pg_temp.id('kevin')), 'not possible while the group is confirmed');

select pg_temp.run('putri', format('select public.confirm_delivered(%L, %L)', pg_temp.gid('p'), pg_temp.gid('p') || '/' || gen_random_uuid() || '.jpg'));
insert into t_bills select user_id, bill_total from public.group_bill_v where group_id = pg_temp.gid('p');

-- Who may mark: members with food only; no session, no stranger, not Nadia.
select pg_temp.fails('stranger', format('select public.mark_taken(%L, true)', pg_temp.gid('p')), 'not a member');
select pg_temp.fails('nadia', format('select public.mark_taken(%L, true)', pg_temp.gid('p')), 'You have no food in this order');
do $$ declare got text; begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin
    set local role anon;
    execute format('select public.mark_taken(%L, true)', pg_temp.gid('p'));
    got := null;
  exception when others then got := sqlerrm;
  end;
  reset role;
  assert got like 'permission denied%', 'anon cannot call mark_taken: ' || coalesce(got, 'no error');
end $$;

-- Putri takes hers, then undoes: no notice either way.
select pg_temp.take('putri', true);
do $$ begin assert pg_temp.taken('p', 'putri'), 'putri taken'; end $$;
select pg_temp.take('putri', false);
do $$ begin
  assert not pg_temp.taken('p', 'putri'), 'undo clears it';
  assert (select count(*) from public.notifications where group_id = pg_temp.gid('p') and kind in ('fridge_clear', 'pickup_nudge')) = 0,
    'self-reports and undo notify nobody';
end $$;

-- The host's pickup nudge: host only, one per member, not the payment nudge.
select pg_temp.fails('putri', format('select public.pickup_nudge(%L, %L)', pg_temp.gid('p'), pg_temp.id('kevin')), 'only the host can do this');
select pg_temp.run('rani', format('select public.pickup_nudge(%L, %L)', pg_temp.gid('p'), pg_temp.id('kevin')));
select pg_temp.fails('rani', format('select public.pickup_nudge(%L, %L)', pg_temp.gid('p'), pg_temp.id('kevin')), 'You already nudged them');
select pg_temp.run('rani', format('select public.pickup_nudge(%L, %L)', pg_temp.gid('p'), pg_temp.id('nadia')));  -- no food: nothing
do $$ begin
  assert pg_temp.notes('p', 'kevin', 'pickup_nudge') = 1, 'one pickup nudge';
  assert pg_temp.notes('p', 'nadia', 'pickup_nudge') = 0, 'nobody nudged without food';
  assert (select title from public.notifications where group_id = pg_temp.gid('p') and kind = 'pickup_nudge')
    = 'Reminder from Rani: your food’s in the fridge', 'nudge title';
  assert (select body from public.notifications where group_id = pg_temp.gid('p') and kind = 'pickup_nudge')
    = 'Brioche Bun and 3 slices of Burnt Cheesecake 20 cm. Tap I’ve taken mine once you have it.', 'nudge body';
  assert (select nudged_at is null and pickup_nudged_at is not null from public.members
          where group_id = pg_temp.gid('p') and user_id = pg_temp.id('kevin')), 'payment nudge untouched';
  assert public.food_list(pg_temp.gid('p'), pg_temp.id('rani')) = '6 slices of Burnt Cheesecake 20 cm', 'owner keeps the rest';
  assert public.food_list(pg_temp.gid('p'), pg_temp.id('putri')) = '2× Pain Au Chocolate and 3 slices of Burnt Cheesecake 20 cm', 'putri list';
end $$;

-- Everyone (host included) takes theirs: one Fridge is clear, to the host.
select pg_temp.take('putri', true), pg_temp.take('kevin', true);
do $$ begin assert pg_temp.notes('p', 'rani', 'fridge_clear') = 0, 'not yet: rani’s slices are still in'; end $$;
select pg_temp.take('rani', true);
do $$ begin
  assert pg_temp.notes('p', 'rani', 'fridge_clear') = 1, 'fridge clear once';
  assert (select count(*) from public.notifications where group_id = pg_temp.gid('p') and kind = 'fridge_clear') = 1, 'host only';
  assert (select body from public.notifications where group_id = pg_temp.gid('p') and kind = 'fridge_clear')
    = 'Everyone has taken their Test p food. Close the order when you’re ready.', 'fridge clear body';
end $$;
select pg_temp.take('kevin', false);
select pg_temp.take('kevin', true);
select pg_temp.take('kevin', true);  -- again: keeps the first time
do $$ begin assert pg_temp.notes('p', 'rani', 'fridge_clear') = 1, 'not again after undo and re-take'; end $$;

-- Bills never move; Close isn't blocked by pickup (only by payment), and Pickup ends with it.
select pg_temp.take('kevin', false);
do $$ begin
  assert not exists (select 1 from public.group_bill_v v join t_bills b on b.user_id = v.user_id
                     where v.group_id = pg_temp.gid('p') and v.bill_total is distinct from b.total), 'bills unchanged';
end $$;
select pg_temp.run('rani', format('select public.confirm_paid(%L, %L)', pg_temp.gid('p'), pg_temp.id('putri')));
select pg_temp.run('rani', format('select public.confirm_paid(%L, %L)', pg_temp.gid('p'), pg_temp.id('kevin')));
select pg_temp.run('rani', format('select public.close_group(%L)', pg_temp.gid('p')));  -- Kevin hasn't taken his
select pg_temp.fails('kevin', format('select public.mark_taken(%L, true)', pg_temp.gid('p')), 'Pickup opens once the order is delivered');
select pg_temp.fails('rani', format('select public.pickup_nudge(%L, %L)', pg_temp.gid('p'), pg_temp.id('kevin')), 'not possible while the group is closed');

delete from public.groups where id in (select v from t_g);

select 'pickup.sql: all assertions passed' as result;
rollback;
