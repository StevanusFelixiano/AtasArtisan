-- The design's sample order end to end, as the real roles. Rolls back; run with execute_sql.
-- Expected bills (Claude Design board 5): Rani 189.500, Dimas 38.500, Putri 99.500, Kevin 89.500,
-- Nadia 52.500, Arief 26.500; items Rp 481.000; ongkir 30.000 − discount 15.000 = 2.500 each.
begin;

create temp table t_ids (k text primary key, v uuid);
insert into t_ids values ('rani', gen_random_uuid()), ('dimas', gen_random_uuid()), ('putri', gen_random_uuid()),
  ('kevin', gen_random_uuid()), ('nadia', gen_random_uuid()), ('arief', gen_random_uuid());
grant select on t_ids to authenticated;
create function pg_temp.id(k text) returns uuid language sql as $$ select v from t_ids where t_ids.k = id.k $$;
create function pg_temp.act(k text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', pg_temp.id(k), 'role', 'authenticated')::text, true)
$$;

insert into auth.users (id, email, aud, role) select v, k || '@test.invalid', 'authenticated', 'authenticated' from t_ids;
insert into public.profiles (id, phone, name) select v, '62812000000' || row_number() over (), initcap(k) from t_ids;

insert into public.products (id, name, base_price, option_groups, variants) values
  ('t-croissant', 'Butter Croissant', 12000, '[]', '[]'),
  ('t-sourdough', 'Classic Sourdough', 21000,
   '[{"name":"Berat","choices":["600gr","1000gr"]},{"name":"Slice","choices":["Whole Sourdough","Sliced 15mm"]}]',
   '[{"options":{"Berat":"600gr","Slice":"Whole Sourdough"},"price":21000},
     {"options":{"Berat":"600gr","Slice":"Sliced 15mm"},"price":21000},
     {"options":{"Berat":"1000gr","Slice":"Whole Sourdough"},"price":33000},
     {"options":{"Berat":"1000gr","Slice":"Sliced 15mm"},"price":33000}]'),
  ('t-cheesecake', 'Burnt Cheesecake 20 cm', 260000, '[]', '[]'),
  ('t-pain', 'Pain Au Chocolate', 16000, '[]', '[]'),
  ('t-cinnamon', 'Cinnamon Roll 60 gr', 10000, '[]', '[]'),
  ('t-brioche', 'Brioche Bun', 8000, '[]', '[]'),
  ('t-muffin', 'English Muffin', 5000, '[]', '[]'),
  ('t-pretzel', 'Pretzel 120 gr', 9000, '[]', '[]'),
  ('t-banana', 'Banana Cake', 50000, '[]', '[]'),
  ('t-cookies', 'Cookies 100 gr', 12000, '[]', '[]');

-- Rani creates the group as herself (column grants + RLS), everyone joins by code.
select pg_temp.act('rani');
set local role authenticated;
insert into public.groups (name, area, delivery_at, cutoff_at) values ('Academy Bali Friday Treats', 'Kuta', now() + interval '1 day', now() + interval '3 hours');
reset role;
create temp table t_g as select id, code from public.groups where host_id = pg_temp.id('rani');
grant select on t_g to authenticated;

do $$ declare k text; begin
  foreach k in array array['dimas','putri','kevin','nadia','arief'] loop
    perform pg_temp.act(k);
    set local role authenticated;
    perform public.join_group((select code from t_g));
    reset role;
  end loop;
end $$;

-- Items, each added by its owner through RLS; unit_price comes from the menu, not the client.
create function pg_temp.add(k text, p text, q int, o jsonb default '{}') returns void language plpgsql as $$
begin
  perform pg_temp.act(k);
  set local role authenticated;
  insert into public.items (group_id, product_id, qty, options) values ((select id from t_g), p, q, o);
  reset role;
end $$;
select pg_temp.add('rani', 't-croissant', 2), pg_temp.add('rani', 't-sourdough', 1, '{"Berat":"1000gr","Slice":"Sliced 15mm"}'),
       pg_temp.add('rani', 't-cheesecake', 1), pg_temp.add('dimas', 't-pain', 1), pg_temp.add('dimas', 't-cinnamon', 2),
       pg_temp.add('putri', 't-pain', 2), pg_temp.add('kevin', 't-brioche', 1), pg_temp.add('kevin', 't-muffin', 1),
       pg_temp.add('kevin', 't-pretzel', 1), pg_temp.add('nadia', 't-banana', 1), pg_temp.add('arief', 't-cookies', 2);

do $$ begin
  assert (select unit_price from public.items where product_id = 't-sourdough') = 33000, 'variant price';
  assert (select discount_notified from public.groups g join t_g on t_g.id = g.id), '200k notice fired';
end $$;

-- Rani splits her cheesecake 50/25/25 with Putri and Kevin; both accept.
do $$ declare s uuid; begin
  perform pg_temp.act('rani'); set local role authenticated;
  s := public.propose_split((select id from public.items where product_id = 't-cheesecake'),
    jsonb_build_array(jsonb_build_object('user', pg_temp.id('rani'), 'pct', 50),
                      jsonb_build_object('user', pg_temp.id('putri'), 'pct', 25),
                      jsonb_build_object('user', pg_temp.id('kevin'), 'pct', 25)));
  reset role;
  perform pg_temp.act('putri'); set local role authenticated; perform public.answer_share(s, true); reset role;
  perform pg_temp.act('kevin'); set local role authenticated; perform public.answer_share(s, true); reset role;
end $$;

-- Lock, send, Atas confirms ongkir 30.000 with a 15.000 discount.
do $$ begin
  perform pg_temp.act('rani'); set local role authenticated;
  perform public.lock_group((select id from t_g));
  perform public.mark_sent((select id from t_g));
  perform public.confirm_atas((select id from t_g), 30000, 15000);
  reset role;
end $$;

-- A non-host can't confirm payments.
do $$ begin
  perform pg_temp.act('dimas'); set local role authenticated;
  begin
    perform public.confirm_paid((select id from t_g), pg_temp.id('dimas'));
    raise exception 'non-host confirmed a payment';
  exception when others then
    if sqlerrm = 'non-host confirmed a payment' then raise; end if;
  end;
  reset role;
end $$;

do $$ begin
  assert (select sum(unit_price * qty) from public.items i join t_g on t_g.id = i.group_id) = 481000, 'items total';
  assert (select bill_total from public.members where user_id = pg_temp.id('rani')) = 189500, 'rani';
  assert (select bill_total from public.members where user_id = pg_temp.id('dimas')) = 38500, 'dimas';
  assert (select bill_total from public.members where user_id = pg_temp.id('putri')) = 99500, 'putri';
  assert (select bill_total from public.members where user_id = pg_temp.id('kevin')) = 89500, 'kevin';
  assert (select bill_total from public.members where user_id = pg_temp.id('nadia')) = 52500, 'nadia';
  assert (select bill_total from public.members where user_id = pg_temp.id('arief')) = 26500, 'arief';
  assert (select count(*) from public.notifications where kind = 'bill_final' and group_id = (select id from t_g)) = 5, 'bill notices';
end $$;

-- Deleting a group with a live split (also what account deletion does) must not trip on its own notices.
delete from public.groups where id = (select id from t_g);

select 'bill.sql: all assertions passed' as result;
rollback;
