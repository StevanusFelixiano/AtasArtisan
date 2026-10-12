-- Per-item pickup, the people limit (share-only members) and the Atas reply reminder, end to end as the real roles.
-- Rolls back; run with execute_sql.
--
-- Pickup: Rani hosts and shares a Burnt Cheesecake in 12 slices; Putri adds 2 Pain Au Chocolate and claims 3 slices.
-- Putri takes her lines one at a time; she counts as taken only once both are.
-- Limit 3 (Rani included): Putri and Kevin join full, Nadia and Dimas share-only. Nadia can claim slices but not add;
-- Kevin leaves, the share-only members hear a spot opened, Nadia adds and takes it, Dimas still can't.
begin;

create temp table t_ids (k text primary key, v uuid);
insert into t_ids values ('rani', gen_random_uuid()), ('putri', gen_random_uuid()), ('kevin', gen_random_uuid()),
  ('nadia', gen_random_uuid()), ('stranger', gen_random_uuid()),
  ('dimas', gen_random_uuid());
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
create function pg_temp.mk(k text, host text, joiners text[], lim int default null) returns void language plpgsql as $$
declare j text; g uuid;
begin
  perform pg_temp.act(host);
  set local role authenticated;
  insert into public.groups (name, area, delivery_at, cutoff_at, pay_rule, people_limit)
    values ('Test ' || k, 'Kuta', now() + interval '1 day', now() + interval '3 hours', 'order_first', lim) returning id into g;
  reset role;
  insert into t_g select k, g, code from public.groups where id = g;
  foreach j in array joiners loop
    perform pg_temp.run(j, format('select public.join_group(%L)', (select code from t_g where t_g.k = mk.k)));
  end loop;
end $$;
create function pg_temp.share_only(g text, k text) returns boolean language sql as $$
  select share_only from public.members where group_id = pg_temp.gid(g) and user_id = pg_temp.id(k)
$$;
create function pg_temp.line(g text, k text, p text) returns boolean language sql as $$
  select exists (select 1 from public.item_pickups where item_id = pg_temp.item(g, p) and user_id = pg_temp.id(k))
$$;
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


insert into auth.users (id, email, aud, role) select v, k || '@test.invalid', 'authenticated', 'authenticated' from t_ids;
insert into public.profiles (id, phone, name) select v, '62813000000' || row_number() over (), initcap(k) from t_ids;
insert into public.products (id, name, base_price, option_groups, variants) values
  ('t-cheesecake', 'Burnt Cheesecake 20 cm', 260000, '[]', '[]'),
  ('t-pain', 'Pain Au Chocolate', 16000, '[]', '[]'),
  ('t-brioche', 'Brioche Bun', 8000, '[]', '[]');

-- ---------------------------------------------------------------- per-item pickup

select pg_temp.mk('p', 'rani', array['putri']);
select pg_temp.add('p', 'rani', 't-cheesecake', 1), pg_temp.add('p', 'putri', 't-pain', 2);
select pg_temp.run('rani', format('select public.share_item(%L, 12, null, 1)', pg_temp.item('p', 't-cheesecake')));
select pg_temp.run('putri', format('select public.claim_pieces(%L, 3)', pg_temp.item('p', 't-cheesecake')));
select pg_temp.run('rani', format('select public.lock_group(%L)', pg_temp.gid('p')));
select pg_temp.run('rani', format('select public.mark_sent(%L)', pg_temp.gid('p')));

-- The Atas reply reminder: not before 30 minutes, once per send.
select public.remind_atas_reply();
do $$ begin assert pg_temp.notes('p', 'rani', 'atas_reply') = 0, 'no reminder yet'; end $$;
update public.groups set sent_at = now() - interval '31 minutes' where id = pg_temp.gid('p');
select public.remind_atas_reply();
select public.remind_atas_reply();
do $$ begin
  assert pg_temp.notes('p', 'rani', 'atas_reply') = 1, 'one reminder';
  assert pg_temp.notes('p', 'putri', 'atas_reply') = 0, 'host only';
  assert (select body from public.notifications where group_id = pg_temp.gid('p') and kind = 'atas_reply')
    = 'Once Atas confirms Test p on WhatsApp, open the order and tap Atas replied to enter the ongkir so everyone knows it’s on.', 'reminder body';
end $$;

select pg_temp.run('rani', format('select public.confirm_atas(%L, null, null)', pg_temp.gid('p')));
select pg_temp.fails('putri', format('select public.mark_item_taken(%L, true)', pg_temp.item('p', 't-pain')), 'Pickup opens once the order is delivered');
select pg_temp.run('putri', format('select public.confirm_delivered(%L, %L)', pg_temp.gid('p'), pg_temp.gid('p') || '/' || gen_random_uuid() || '.jpg'));

-- Not someone else's line.
select pg_temp.fails('rani', format('select public.mark_item_taken(%L, true)', pg_temp.item('p', 't-pain')), 'This isn’t your food');

-- Putri: one line, then the other; Undo of one puts her back.
select pg_temp.run('putri', format('select public.mark_item_taken(%L, true)', pg_temp.item('p', 't-pain')));
do $$ begin
  assert pg_temp.line('p', 'putri', 't-pain') and not pg_temp.taken('p', 'putri'), 'one of two lines: not taken yet';
end $$;
select pg_temp.run('putri', format('select public.mark_item_taken(%L, true)', pg_temp.item('p', 't-cheesecake')));
do $$ begin assert pg_temp.taken('p', 'putri'), 'both lines: taken'; end $$;
select pg_temp.run('putri', format('select public.mark_item_taken(%L, false)', pg_temp.item('p', 't-cheesecake')));
do $$ begin
  assert not pg_temp.taken('p', 'putri') and pg_temp.line('p', 'putri', 't-pain'), 'undo one line';
  assert pg_temp.notes('p', 'rani', 'fridge_clear') = 0, 'nobody clear yet';
end $$;

-- I've taken mine marks every line; Undo clears every line.
select pg_temp.take('putri', true);
do $$ begin assert pg_temp.taken('p', 'putri') and pg_temp.line('p', 'putri', 't-cheesecake'), 'all lines'; end $$;
select pg_temp.take('putri', false);
do $$ begin assert not pg_temp.line('p', 'putri', 't-pain') and not pg_temp.taken('p', 'putri'), 'undo all'; end $$;

-- Last line in: Fridge is clear, once.
select pg_temp.run('rani', format('select public.mark_item_taken(%L, true)', pg_temp.item('p', 't-cheesecake')));
select pg_temp.run('putri', format('select public.mark_item_taken(%L, true)', pg_temp.item('p', 't-pain')));
select pg_temp.run('putri', format('select public.mark_item_taken(%L, true)', pg_temp.item('p', 't-cheesecake')));
do $$ begin assert pg_temp.notes('p', 'rani', 'fridge_clear') = 1, 'fridge clear once'; end $$;

-- ---------------------------------------------------------------- people limit

select pg_temp.mk('l', 'rani', array['putri', 'kevin', 'nadia', 'dimas'], 3);
do $$ begin
  assert not pg_temp.share_only('l', 'rani') and not pg_temp.share_only('l', 'putri') and not pg_temp.share_only('l', 'kevin'), 'first 3 full';
  assert pg_temp.share_only('l', 'nadia') and pg_temp.share_only('l', 'dimas'), 'past the limit: share-only';
  assert (select title from public.notifications where group_id = pg_temp.gid('l') and kind = 'joined'
          and title like 'Nadia%') = 'Nadia joined Test l to share', 'host told nadia joined to share';
end $$;

-- Preview: full, and a newcomer would join share-only.
do $$ declare p record; begin
  perform pg_temp.act('stranger');
  select * into p from public.group_preview((select code from t_g where k = 'l'));
  assert p.people_limit = 3 and p.full_members = 3 and p.share_only, 'preview says share-only';
end $$;

select pg_temp.add('l', 'rani', 't-cheesecake', 1), pg_temp.add('l', 'kevin', 't-brioche', 1);
select pg_temp.run('rani', format('select public.share_item(%L, 12, null, 1)', pg_temp.item('l', 't-cheesecake')));
select pg_temp.fails('nadia', format('insert into public.items (group_id, product_id, qty, options) values (%L, %L, 1, %L)',
  pg_temp.gid('l'), 't-pain', '{}'), 'This group is full (3 people). You can still join shared items.');
select pg_temp.run('nadia', format('select public.claim_pieces(%L, 2)', pg_temp.item('l', 't-cheesecake')));
do $$ begin
  assert (select pieces from public.item_claims where item_id = pg_temp.item('l', 't-cheesecake') and user_id = pg_temp.id('nadia')) = 2,
    'share-only can claim';
end $$;

-- Kevin leaves: the share-only members hear a spot opened; the first to add takes it.
select pg_temp.run('kevin', format('select public.leave_group(%L)', pg_temp.gid('l')));
do $$ begin
  assert pg_temp.notes('l', 'nadia', 'spot_open') = 1 and pg_temp.notes('l', 'dimas', 'spot_open') = 1, 'share-only told';
  assert pg_temp.notes('l', 'putri', 'spot_open') = 0, 'full members not told';
end $$;
select pg_temp.add('l', 'nadia', 't-pain', 1);
do $$ begin assert not pg_temp.share_only('l', 'nadia'), 'nadia took the spot'; end $$;
select pg_temp.fails('dimas', format('insert into public.items (group_id, product_id, qty, options) values (%L, %L, 1, %L)',
  pg_temp.gid('l'), 't-pain', '{}'), 'This group is full (3 people)%');

-- The host raises the limit: Dimas hears, and can add.
select pg_temp.run('rani', format('update public.groups set people_limit = 4 where id = %L', pg_temp.gid('l')));
do $$ begin assert pg_temp.notes('l', 'dimas', 'spot_open') = 2, 'dimas told again'; end $$;
select pg_temp.add('l', 'dimas', 't-brioche', 1);
do $$ begin assert not pg_temp.share_only('l', 'dimas'), 'dimas full'; end $$;

-- A share-only member removed by the host frees no spot: nobody is told.
select pg_temp.run('stranger', format('select public.join_group(%L)', (select code from t_g where k = 'l')));
do $$ begin assert pg_temp.share_only('l', 'stranger'), 'stranger share-only'; end $$;
select pg_temp.run('rani', format('select public.remove_member(%L, %L)', pg_temp.gid('l'), pg_temp.id('stranger')));
do $$ begin assert (select count(*) from public.notifications where group_id = pg_temp.gid('l') and kind = 'spot_open') = 3, 'no new spot notices'; end $$;

delete from public.groups where id in (select v from t_g);

select 'limit_pickup.sql: all assertions passed' as result;
rollback;
