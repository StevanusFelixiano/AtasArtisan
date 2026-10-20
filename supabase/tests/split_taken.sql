-- Shared items after lock (board 10): marking someone else's pieces taken, the whole item at once, Put back, and the
-- #31 / #32 pushes, end to end as the real roles. Rolls back; run with execute_sql.
--
-- Rani hosts; she shares her Burnt Cheesecake 20 cm (Rp 260.000) in 12 slices, keeping 1: Putri claims 3, Kevin 2, so
-- Rani holds 7. Nadia orders a Pain Au Chocolate and isn't in the split.
-- Checks: only Delivered, only people holding pieces of that item, only holders of it; a mark records who did it and
-- sends nothing until it is 4 s old (split_taken_push, the cron job), so an undo within the window notifies nobody;
-- one #31 per marked row, the whole-item copy once every holder is out; Put back after #31 sends #32; the owner marks
-- too; marks count toward Fridge is clear; bills never move.
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
-- k's cheesecake line: is it out of the fridge, and who marked it (null: k did, or nobody).
create function pg_temp.is_out(k text) returns boolean language sql as $$
  select exists (select 1 from public.item_pickups where item_id = pg_temp.item('s', 't-cheesecake') and user_id = pg_temp.id(k))
$$;
create function pg_temp.marker(k text) returns uuid language sql as $$
  select marked_by from public.item_pickups where item_id = pg_temp.item('s', 't-cheesecake') and user_id = pg_temp.id(k)
$$;
-- `k` marks `holder`'s cheesecake slices (null: every holder) taken or puts them back.
create function pg_temp.split(k text, holder text, taken boolean) returns void language sql as $$
  select pg_temp.run(k, format('select public.mark_split_taken(%L, %L, %L)', pg_temp.item('s', 't-cheesecake'), pg_temp.id(holder), taken))
$$;
-- The cron job, once the marks are past the app's 4 s Undo (now() is fixed inside this transaction).
create function pg_temp.push_later() returns void language sql as $$
  update public.item_pickups set taken_at = taken_at - interval '1 minute' where group_id = pg_temp.gid('s');
  select public.split_taken_push();
$$;
create function pg_temp.latest(k text, kind text) returns text language sql as $$
  select title || ' | ' || body from public.notifications
  where group_id = pg_temp.gid('s') and user_id = pg_temp.id(k) and notifications.kind = latest.kind order by id desc limit 1
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

insert into auth.users (id, email, aud, role) select v, k || '@test.invalid', 'authenticated', 'authenticated' from t_ids;
insert into public.profiles (id, phone, name) select v, '62813000000' || row_number() over (), initcap(k) from t_ids;
insert into public.products (id, name, base_price, option_groups, variants) values
  ('t-cheesecake', 'Burnt Cheesecake 20 cm', 260000, '[]', '[]'),
  ('t-pain', 'Pain Au Chocolate', 16000, '[]', '[]');

select pg_temp.mk('s', 'rani', array['putri','kevin','nadia']);
select pg_temp.add('s', 'rani', 't-cheesecake', 1), pg_temp.add('s', 'nadia', 't-pain', 1);
select pg_temp.run('rani', format('select public.share_item(%L, 12, null, 1)', pg_temp.item('s', 't-cheesecake')));
select pg_temp.run('putri', format('select public.claim_pieces(%L, 3)', pg_temp.item('s', 't-cheesecake')));
select pg_temp.run('kevin', format('select public.claim_pieces(%L, 2)', pg_temp.item('s', 't-cheesecake')));
select pg_temp.run('rani', format('select public.lock_group(%L)', pg_temp.gid('s')));
select pg_temp.run('rani', format('select public.mark_sent(%L)', pg_temp.gid('s')));
select pg_temp.run('rani', format('select public.confirm_atas(%L, null, null)', pg_temp.gid('s')));

-- Not before Delivered.
select pg_temp.fails('putri', format('select public.mark_split_taken(%L, %L, true)', pg_temp.item('s', 't-cheesecake'), pg_temp.id('kevin')),
  'Pickup opens once the order is delivered');

select pg_temp.run('putri', format('select public.confirm_delivered(%L, %L)', pg_temp.gid('s'), pg_temp.gid('s') || '/' || gen_random_uuid() || '.jpg'));
insert into t_bills select user_id, bill_total from public.group_bill_v where group_id = pg_temp.gid('s');
do $$ begin
  assert public.split_pieces(pg_temp.item('s', 't-cheesecake'), pg_temp.id('rani')) = 7, 'rani holds the 7 nobody claimed';
  assert (select count(*) from public.split_holders(pg_temp.item('s', 't-cheesecake'))) = 3, 'three holders';
end $$;

-- Who may mark: members holding pieces of that item, for its holders only, on shared items only.
select pg_temp.fails('stranger', format('select public.mark_split_taken(%L, null, true)', pg_temp.item('s', 't-cheesecake')), 'not found');
select pg_temp.fails('nadia', format('select public.mark_split_taken(%L, %L, true)', pg_temp.item('s', 't-cheesecake'), pg_temp.id('kevin')),
  'You’re not in this split');
select pg_temp.fails('putri', format('select public.mark_split_taken(%L, %L, true)', pg_temp.item('s', 't-cheesecake'), pg_temp.id('nadia')),
  'They’re not in this split');
select pg_temp.fails('nadia', format('select public.mark_split_taken(%L, null, true)', pg_temp.item('s', 't-pain')), 'This item isn’t shared');
select pg_temp.fails('putri', 'select public.split_taken_push()', 'permission denied%');
do $$ declare got text; begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin
    set local role anon;
    execute format('select public.mark_split_taken(%L, null, true)', pg_temp.item('s', 't-cheesecake'));
    got := null;
  exception when others then got := sqlerrm;
  end;
  reset role;
  assert got like 'permission denied%', 'anon cannot call mark_split_taken: ' || coalesce(got, 'no error');
end $$;
do $$ begin assert not exists (select 1 from public.item_pickups where group_id = pg_temp.gid('s')), 'refusals mark nothing'; end $$;

-- Putri marks Kevin's 2 slices: his line is out, marked by her; his only food, so he counts as taken. Nobody else moves.
select pg_temp.split('putri', 'kevin', true);
do $$ begin
  assert pg_temp.is_out('kevin') and pg_temp.marker('kevin') = pg_temp.id('putri'), 'kevin marked by putri';
  assert not pg_temp.is_out('putri') and not pg_temp.is_out('rani'), 'only kevin';
  assert pg_temp.taken('s', 'kevin'), 'kevin counts as taken';
end $$;

-- Undo inside the toast: the line goes back and nobody hears of either tap.
select pg_temp.split('putri', 'kevin', false);
select public.split_taken_push();
do $$ begin
  assert not pg_temp.is_out('kevin') and not pg_temp.taken('s', 'kevin'), 'undo puts kevin back';
  assert (select count(*) from public.notifications where group_id = pg_temp.gid('s') and kind in ('split_taken', 'split_put_back')) = 0,
    'an undone mark notifies nobody';
end $$;

-- Marked again: nothing until the mark is 4 s old, then one #31b to Kevin, once.
select pg_temp.split('putri', 'kevin', true);
select public.split_taken_push();
do $$ begin assert pg_temp.notes('s', 'kevin', 'split_taken') = 0, 'not inside the undo window'; end $$;
select pg_temp.push_later();
select public.split_taken_push();
do $$ begin
  assert pg_temp.notes('s', 'kevin', 'split_taken') = 1, 'one push for the mark';
  assert pg_temp.latest('kevin', 'split_taken')
    = 'Putri took your Burnt Cheesecake 20 cm slices | Your 2 Burnt Cheesecake 20 cm slices are out of the fridge, with Putri.', '#31b copy';
  assert (select notified_at is not null from public.item_pickups where item_id = pg_temp.item('s', 't-cheesecake') and user_id = pg_temp.id('kevin')),
    'notified_at set';
  assert pg_temp.notes('s', 'putri', 'split_taken') = 0, 'nobody hears of their own taps';
end $$;

-- Put back after #31 went out: Kevin hears his slices are back (#32).
select pg_temp.split('putri', 'kevin', false);
do $$ begin
  assert not pg_temp.is_out('kevin') and not pg_temp.taken('s', 'kevin'), 'kevin back in the fridge';
  assert pg_temp.notes('s', 'kevin', 'split_put_back') = 1, 'one put-back notice';
  assert pg_temp.latest('kevin', 'split_put_back')
    = 'Your Burnt Cheesecake 20 cm slices are back in the fridge | Putri put your 2 Burnt Cheesecake 20 cm slices back. They’re still yours to take.',
    '#32 copy';
end $$;

-- "I took the whole cheesecake": every holder at once, Putri's own line as a self-mark.
select pg_temp.split('putri', null, true);
do $$ begin
  assert pg_temp.is_out('rani') and pg_temp.is_out('putri') and pg_temp.is_out('kevin'), 'every holder out';
  assert pg_temp.marker('rani') = pg_temp.id('putri') and pg_temp.marker('kevin') = pg_temp.id('putri'), 'marked by putri';
  assert pg_temp.marker('putri') is null, 'her own line is a self-mark';
  assert pg_temp.taken('s', 'rani') and pg_temp.taken('s', 'putri') and pg_temp.taken('s', 'kevin'), 'all three taken';
  assert not pg_temp.is_out('nadia') and not pg_temp.taken('s', 'nadia'), 'never anyone else’s food';
  assert pg_temp.notes('s', 'rani', 'fridge_clear') = 0, 'nadia’s pastry is still in';
end $$;
select pg_temp.push_later();
do $$ begin
  assert pg_temp.notes('s', 'rani', 'split_taken') = 1 and pg_temp.notes('s', 'kevin', 'split_taken') = 2
     and pg_temp.notes('s', 'putri', 'split_taken') = 0, 'one push per row someone else marked';
  assert (select count(*) from public.notifications where group_id = pg_temp.gid('s') and kind = 'split_taken') = 3, 'three in all';
  assert pg_temp.latest('rani', 'split_taken')
    = 'Putri took the Burnt Cheesecake 20 cm out of the fridge | Your 7 slices are with Putri.', '#31a copy';
  assert pg_temp.latest('kevin', 'split_taken')
    = 'Putri took the Burnt Cheesecake 20 cm out of the fridge | Your 2 slices are with Putri.', '#31a for kevin';
end $$;

-- The owner marks and puts back too. Putri's self-marked line was never pushed, so putting it back sends nothing.
select pg_temp.split('rani', 'putri', false);
select pg_temp.split('rani', 'putri', true);
do $$ begin
  assert pg_temp.notes('s', 'putri', 'split_put_back') = 0, 'no #32 without a #31';
  assert pg_temp.marker('putri') = pg_temp.id('rani'), 'marked by the owner';
end $$;

-- Marks count toward Fridge is clear like self-marks; bills never move.
select pg_temp.run('nadia', format('select public.mark_taken(%L, true)', pg_temp.gid('s')));
do $$ begin
  assert pg_temp.notes('s', 'rani', 'fridge_clear') = 1, 'fridge clear once everyone is out';
  assert not exists (select 1 from public.group_bill_v v join t_bills b on b.user_id = v.user_id
                     where v.group_id = pg_temp.gid('s') and v.bill_total is distinct from b.total), 'bills unchanged';
end $$;

-- Still open once the order is Closed.
update public.groups set state = 'closed' where id = pg_temp.gid('s');
select pg_temp.split('kevin', 'putri', false);
do $$ begin assert not pg_temp.is_out('putri'), 'put back after close'; end $$;

delete from public.groups where id in (select v from t_g);

select 'split_taken.sql: all assertions passed' as result;
rollback;
