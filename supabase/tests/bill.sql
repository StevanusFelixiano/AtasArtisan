-- The bill, shared items, pay first and closing, end to end as the real roles. Rolls back; run with execute_sql.
--
-- 1 Order first, Rp 200.000 or more (the design's sample order, Rp 481.000):
--   Rani shares her Burnt Cheesecake (Rp 260.000) in 12 pieces, minimum 3: Kevin claims 3, Putri 2 → met.
--   Kevin pays ⌊260.000 × 3 ÷ 12⌋ = 65.000, Putri ⌊260.000 × 2 ÷ 12⌋ = 43.333, Rani the rest 151.667.
--   Nadia shares her Banana Cake (Rp 50.000) in 8 pieces, minimum 4; only Arief joins → removed at lock.
--   Dimas asks Kevin to share his Pretzel (Rp 9.000) in 2 pieces, 1 for him; Kevin shares → 4.500 each.
--   Subtotal after lock Rp 431.000 → free ongkir: Atas's 30.000 − 15.000 is ignored.
--   Bills: Rani 208.667, Dimas 40.500, Putri 75.333, Kevin 82.500, Nadia 0, Arief 24.000.
--   Close is refused until everyone has paid.
-- 2 Pay first under Rp 200.000 (Rp 64.000; Rani, Putri, Kevin order, Nadia doesn't):
--   Ongkir 25.000 among 3 → 8.300, 8.300, host 8.400. Re-entering it: paid members owe only the difference.
--   Discount 40.000: Kevin's bill stops at 0, the host takes the remainder. Discount is capped at items + ongkir.
--   Payments made before sending survive Atas's confirmation.
-- 3 Pay first at Rp 200.000 or more: bills are final at lock (tick auto-lock), members can pay before sending.
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
-- Run a statement as a user; it must succeed.
create function pg_temp.run(k text, q text) returns void language plpgsql as $$
begin
  perform pg_temp.act(k);
  set local role authenticated;
  execute q;
  reset role;
end $$;
-- Run a statement as a user; it must fail with an error like `want`.
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
create function pg_temp.bill(g text, k text) returns int language sql as $$
  select bill_total from public.group_bill_v where group_id = pg_temp.gid(g) and user_id = pg_temp.id(k)
$$;
create function pg_temp.share(g text, k text) returns int language sql as $$
  select delivery_share from public.group_bill_v where group_id = pg_temp.gid(g) and user_id = pg_temp.id(k)
$$;
create function pg_temp.notes(g text, k text, kind text) returns int language sql as $$
  select count(*)::int from public.notifications where group_id = pg_temp.gid(g) and user_id = pg_temp.id(k) and notifications.kind = notes.kind
$$;
-- A group created by its host through RLS, joined by code.
create function pg_temp.mk(k text, host text, rule text, joiners text[]) returns void language plpgsql as $$
declare j text; g uuid;
begin
  perform pg_temp.act(host);
  set local role authenticated;
  insert into public.groups (name, area, delivery_at, cutoff_at, pay_rule)
    values ('Test ' || k, 'Kuta', now() + interval '1 day', now() + interval '3 hours', rule) returning id into g;
  reset role;
  insert into t_g select k, g, code from public.groups where id = g;
  foreach j in array joiners loop
    perform pg_temp.run(j, format('select public.join_group(%L)', (select code from t_g where t_g.k = mk.k)));
  end loop;
end $$;
create function pg_temp.add(g text, k text, p text, q int, o jsonb default '{}') returns void language plpgsql as $$
begin
  perform pg_temp.act(k);
  set local role authenticated;
  insert into public.items (group_id, product_id, qty, options) values (pg_temp.gid(g), p, q, o);
  reset role;
end $$;

insert into auth.users (id, email, aud, role) select v, k || '@test.invalid', 'authenticated', 'authenticated' from t_ids;
insert into public.profiles (id, phone, name) select v, '62812000000' || row_number() over (), initcap(k) from t_ids;

insert into public.products (id, name, base_price, option_groups, variants) values
  ('t-croissant', 'Butter Croissant', 12000, '[]', '[]'),
  ('t-sourdough', 'Classic Sourdough', 21000,
   '[{"name":"Berat","choices":["600gr","1000gr"]},{"name":"Slice","choices":["Whole Sourdough","Sliced 15mm"]}]',
   '[{"options":{"Berat":"600gr","Slice":"Whole Sourdough"},"price":21000},
     {"options":{"Berat":"600gr","Slice":"Sliced 15mm"},"price":21000},
     {"options":{"Berat":"1000gr","Slice":"Whole Sourdough"},"price":33000,"image":"https://cdn.example/sourdough.png"},
     {"options":{"Berat":"1000gr","Slice":"Sliced 15mm"},"price":33000}]'),
  ('t-cheesecake', 'Burnt Cheesecake 20 cm', 260000, '[]', '[]'),
  ('t-pain', 'Pain Au Chocolate', 16000, '[]', '[]'),
  ('t-cinnamon', 'Cinnamon Roll 60 gr', 10000, '[]', '[]'),
  ('t-brioche', 'Brioche Bun', 8000, '[]', '[]'),
  ('t-muffin', 'English Muffin', 5000, '[]', '[]'),
  ('t-pretzel', 'Pretzel 120 gr', 9000, '[]', '[]'),
  ('t-banana', 'Banana Cake', 50000, '[]', '[]'),
  ('t-cookies', 'Cookies 100 gr', 12000, '[]', '[]');

-- ================================================================ 1 · order first, shared items, free ongkir

select pg_temp.mk('main', 'rani', 'order_first', array['dimas','putri','kevin','nadia','arief']);
select pg_temp.add('main', 'rani', 't-croissant', 2), pg_temp.add('main', 'rani', 't-sourdough', 1, '{"Berat":"1000gr","Slice":"Sliced 15mm"}'),
       pg_temp.add('main', 'rani', 't-cheesecake', 2), pg_temp.add('main', 'dimas', 't-pain', 1), pg_temp.add('main', 'dimas', 't-cinnamon', 2),
       pg_temp.add('main', 'putri', 't-pain', 2), pg_temp.add('main', 'kevin', 't-brioche', 1), pg_temp.add('main', 'kevin', 't-muffin', 1),
       pg_temp.add('main', 'kevin', 't-pretzel', 1), pg_temp.add('main', 'nadia', 't-banana', 1), pg_temp.add('main', 'arief', 't-cookies', 2);

do $$ begin
  assert (select unit_price from public.items where id = pg_temp.item('main', 't-sourdough')) = 33000, 'variant price (image key ignored)';
  assert (select discount_notified from public.groups where id = pg_temp.gid('main')), 'free-ongkir notice fired';
end $$;

-- Who may share and claim.
select pg_temp.fails('kevin', format('select public.share_item(%L, 12, 3)', pg_temp.item('main', 't-cheesecake')), 'Only the owner%');
select pg_temp.fails('rani', format('select public.share_item(%L, 25, null)', pg_temp.item('main', 't-cheesecake')), 'Pieces must be between 2 and 24');
select pg_temp.fails('kevin', format('select public.claim_pieces(%L, 1)', pg_temp.item('main', 't-cheesecake')), 'This item isn’t shared');
select pg_temp.run('rani', format('select public.share_item(%L, 12, 3)', pg_temp.item('main', 't-cheesecake')));
select pg_temp.fails('rani', format('select public.claim_pieces(%L, 1)', pg_temp.item('main', 't-cheesecake')), 'You can’t claim pieces of your own item');
select pg_temp.run('kevin', format('select public.claim_pieces(%L, 5)', pg_temp.item('main', 't-cheesecake')));
select pg_temp.run('kevin', format('select public.claim_pieces(%L, 3)', pg_temp.item('main', 't-cheesecake')));  -- edits down
select pg_temp.run('putri', format('select public.claim_pieces(%L, 2)', pg_temp.item('main', 't-cheesecake')));
select pg_temp.fails('dimas', format('select public.claim_pieces(%L, 8)', pg_temp.item('main', 't-cheesecake')), 'Only 6 pieces left');  -- Rani keeps 1
select pg_temp.run('dimas', format('select public.claim_pieces(%L, 1)', pg_temp.item('main', 't-cheesecake')));
select pg_temp.run('dimas', format('select public.claim_pieces(%L, 0)', pg_temp.item('main', 't-cheesecake')));  -- withdraws
-- The owner keeps 1 … pieces − 1, and claims stop at what they keep.
select pg_temp.fails('rani', format('select public.share_item(%L, 12, 3, 12)', pg_temp.item('main', 't-cheesecake')), 'Keep between 1 and 11 pieces for yourself');
select pg_temp.fails('rani', format('select public.share_item(%L, 12, 3, 8)', pg_temp.item('main', 't-cheesecake')), '5 pieces already claimed, so you can keep at most 7 pieces');
select pg_temp.run('rani', format('select public.share_item(%L, 12, 3, 7)', pg_temp.item('main', 't-cheesecake')));
select pg_temp.fails('dimas', format('select public.claim_pieces(%L, 1)', pg_temp.item('main', 't-cheesecake')), 'Only 0 pieces left');
select pg_temp.run('rani', format('select public.share_item(%L, 12, 3, 1)', pg_temp.item('main', 't-cheesecake')));
select pg_temp.fails('rani', format('select public.share_item(%L, 4, 3)', pg_temp.item('main', 't-cheesecake')), 'Pieces must be at least 6: 5 claimed plus 1 for you');

select pg_temp.run('nadia', format('select public.share_item(%L, 8, 4)', pg_temp.item('main', 't-banana')));
select pg_temp.run('arief', format('select public.claim_pieces(%L, 2)', pg_temp.item('main', 't-banana')));

-- Ask to share: Dimas asks for 1 of 2 pieces of Kevin's pretzel; sharing claims it for him.
select pg_temp.fails('dimas', format('select public.ask_to_share(%L, 2, 2)', pg_temp.item('main', 't-pretzel')), 'Ask for between 1 and 1 pieces');
select pg_temp.run('dimas', format('select public.ask_to_share(%L, 2, 1)', pg_temp.item('main', 't-pretzel')));
select pg_temp.run('dimas', format('select public.ask_to_share(%L, 2, 1)', pg_temp.item('main', 't-pretzel')));  -- asking again: one request, one push
select pg_temp.run('kevin', format('select public.share_item(%L, 2, null)', pg_temp.item('main', 't-pretzel')));

do $$ begin
  assert (select qty from public.items where id = pg_temp.item('main', 't-cheesecake')) = 1, 'sharing sets qty to 1';
  assert pg_temp.notes('main', 'kevin', 'share_asked') = 1, 'one ask-to-share push';
  assert (select state from public.share_requests where item_id = pg_temp.item('main', 't-pretzel')) = 'accepted', 'request accepted';
  assert (select pieces from public.item_claims where item_id = pg_temp.item('main', 't-pretzel') and user_id = pg_temp.id('dimas')) = 1, 'asker claimed';
  assert pg_temp.notes('main', 'putri', 'item_shared') = 3, 'group told of three shared items';
  assert (select count(*) from public.notifications where kind = 'piece_claimed' and push) = 0, 'piece_claimed is in-app only';
  assert pg_temp.notes('main', 'rani', 'piece_claimed') >= 2, 'owner sees claims';
  -- Live bill before lock: claims count, no delivery.
  assert (select items from public.group_bill_v where group_id = pg_temp.gid('main') and user_id = pg_temp.id('kevin')) = 82500, 'kevin live';
  assert (select items from public.group_bill_v where group_id = pg_temp.gid('main') and user_id = pg_temp.id('rani')) = 208667, 'rani live';
  assert not (select bool_or(is_final) from public.group_bill_v where group_id = pg_temp.gid('main')), 'not final while open';
  -- A shared item can't be bumped above 1 by an old client.
  begin
    update public.items set qty = 2 where id = pg_temp.item('main', 't-cheesecake');
    raise exception 'qty 2 on a shared item';
  exception when check_violation then null;
  end;
end $$;

-- An old-style split, still pending at lock, can't be answered afterwards.
create temp table t_split as select null::uuid as v;
grant select, update on t_split to authenticated;
select pg_temp.run('putri', format($q$update t_split set v = public.propose_split(%L, '[{"user":"%s","pct":50},{"user":"%s","pct":50}]')$q$,
  pg_temp.item('main', 't-cinnamon'), pg_temp.id('dimas'), pg_temp.id('putri')));

-- Lock: the banana cake (2 of 4 people) comes off; the cheesecake (3 of 3) and pretzel stay.
select pg_temp.run('rani', format('select public.lock_group(%L)', pg_temp.gid('main')));

do $$ begin
  assert pg_temp.item('main', 't-banana') is null, 'banana removed at lock';
  assert not exists (select 1 from public.item_claims where group_id = pg_temp.gid('main') and user_id = pg_temp.id('arief')), 'arief claim released';
  assert pg_temp.notes('main', 'nadia', 'share_min_not_met') = 1, 'owner told: min not met';
  assert pg_temp.notes('main', 'arief', 'share_min_not_met') = 1, 'joiner told: min not met';
  assert pg_temp.notes('main', 'arief', 'share_stopped') = 0, 'no stop-sharing notice at lock';
  assert pg_temp.notes('main', 'rani', 'share_locked_in') = 1 and pg_temp.notes('main', 'kevin', 'share_locked_in') = 1
     and pg_temp.notes('main', 'putri', 'share_locked_in') = 1, 'min met notices';
  assert public.group_subtotal(pg_temp.gid('main')) = 431000, 'subtotal after removal';
end $$;
select pg_temp.fails('dimas', format('select public.answer_share(%L, true)', (select v from t_split)), 'not part of this split');
select pg_temp.fails('putri', format('select public.respond_split(%L, true)', (select v from t_split)), 'not yours to answer');
select pg_temp.fails('dimas', format('select public.respond_split(%L, true)', (select v from t_split)), 'Splits can only be answered while the group is open');
select pg_temp.fails('kevin', format('select public.claim_pieces(%L, 4)', pg_temp.item('main', 't-cheesecake')), 'Pieces can only be claimed while the group is open');
select pg_temp.fails('putri', format('select public.claim_paid(%L)', pg_temp.gid('main')), 'The bill is not final yet');
select pg_temp.fails('rani', format('select public.set_bill(%L, 1000, 0)', pg_temp.gid('main')), 'Only pay-first groups%');

-- Send; Atas confirms with ongkir and a discount, which don't apply at Rp 200.000 or more.
select pg_temp.run('rani', format('select public.mark_sent(%L)', pg_temp.gid('main')));
select pg_temp.run('rani', format('select public.confirm_atas(%L, 30000, 15000)', pg_temp.gid('main')));
select pg_temp.fails('dimas', format('select public.confirm_paid(%L, %L)', pg_temp.gid('main'), pg_temp.id('dimas')), 'only the host can do this');

do $$ begin
  assert (select ongkir = 0 and discount = 0 and ongkir_set_at is null and bill_final_at is not null
          from public.groups where id = pg_temp.gid('main')), 'free ongkir';
  assert pg_temp.bill('main', 'rani') = 208667, 'rani';
  assert pg_temp.bill('main', 'dimas') = 40500, 'dimas';
  assert pg_temp.bill('main', 'putri') = 75333, 'putri';
  assert pg_temp.bill('main', 'kevin') = 82500, 'kevin';
  assert pg_temp.bill('main', 'nadia') = 0, 'nadia';
  assert pg_temp.bill('main', 'arief') = 24000, 'arief';
  assert (select sum(bill_total) from public.group_bill_v where group_id = pg_temp.gid('main')) = 431000, 'bills add up';
  assert (select sum(delivery_share) from public.group_bill_v where group_id = pg_temp.gid('main')) = 0, 'no ongkir';
  assert (select count(*) from public.notifications where kind = 'bill_final' and group_id = pg_temp.gid('main')) = 4, 'bill notices';
  assert (select paid_at is not null from public.members where group_id = pg_temp.gid('main') and user_id = pg_temp.id('nadia')), 'zero bill is paid';
end $$;

-- Delivered; Close waits for Dimas, Putri, Kevin and Arief.
select pg_temp.run('dimas', format('select public.confirm_delivered(%L, %L)', pg_temp.gid('main'), pg_temp.gid('main') || '/' || gen_random_uuid() || '.jpg'));
select pg_temp.run('putri', format('select public.claim_paid(%L)', pg_temp.gid('main')));
select pg_temp.run('rani', format('select public.confirm_paid(%L, %L)', pg_temp.gid('main'), pg_temp.id('putri')));
select pg_temp.run('rani', format('select public.confirm_paid(%L, %L)', pg_temp.gid('main'), pg_temp.id('dimas')));   -- cash, no claim
select pg_temp.run('rani', format('select public.nudge(%L, %L)', pg_temp.gid('main'), pg_temp.id('kevin')));
select pg_temp.fails('rani', format('select public.nudge(%L, %L)', pg_temp.gid('main'), pg_temp.id('kevin')), 'You nudged them less than 4 hours ago');
select pg_temp.fails('rani', format('select public.close_group(%L)', pg_temp.gid('main')), 'Everyone has to pay before the order can be closed');
select pg_temp.run('rani', format('select public.confirm_paid(%L, %L)', pg_temp.gid('main'), pg_temp.id('kevin')));
select pg_temp.fails('rani', format('select public.close_group(%L)', pg_temp.gid('main')), 'Everyone has to pay%');
select pg_temp.run('rani', format('select public.confirm_paid(%L, %L)', pg_temp.gid('main'), pg_temp.id('arief')));
select pg_temp.run('rani', format('select public.close_group(%L)', pg_temp.gid('main')));

do $$ begin
  assert (select state from public.groups where id = pg_temp.gid('main')) = 'closed', 'closed once everyone paid';
  assert (select title from public.notifications where group_id = pg_temp.gid('main') and user_id = pg_temp.id('dimas')
          and kind = 'payment_confirmed') = 'Rani marked your Rp 40.500 as paid', 'mark-paid copy';
  assert (select title from public.notifications where group_id = pg_temp.gid('main') and user_id = pg_temp.id('kevin')
          and kind = 'nudge') = 'Rani is waiting for Rp 82.500', 'delivered nudge copy';
  assert pg_temp.notes('main', 'rani', 'everyone_paid') = 1, 'everyone paid once';
end $$;

-- ================================================================ 2 · pay first under Rp 200.000

select pg_temp.mk('small', 'rani', 'pay_first', array['putri','kevin','nadia']);
select pg_temp.add('small', 'rani', 't-croissant', 2), pg_temp.add('small', 'putri', 't-pain', 2), pg_temp.add('small', 'kevin', 't-brioche', 1);
select pg_temp.run('rani', format('select public.lock_group(%L)', pg_temp.gid('small')));
select pg_temp.fails('rani', format($q$update public.groups set pay_rule = 'order_first' where id = %L$q$, pg_temp.gid('small')),
  'The payment flow can only change while the group is open');

do $$ begin
  assert (select bill_final_at is null from public.groups where id = pg_temp.gid('small')), 'asking Atas: not final';
  assert pg_temp.notes('small', 'putri', 'locked') = 1, 'asking-Atas lock notice';
end $$;
select pg_temp.fails('putri', format('select public.claim_paid(%L)', pg_temp.gid('small')), 'The bill is not final yet');
select pg_temp.fails('rani', format('select public.confirm_paid(%L, %L)', pg_temp.gid('small'), pg_temp.id('putri')), 'The bill is not final yet');
select pg_temp.fails('putri', format('select public.set_bill(%L, 25000, 0)', pg_temp.gid('small')), 'only the host can do this');
select pg_temp.run('rani', format('select public.mark_ongkir_asked(%L)', pg_temp.gid('small')));
select pg_temp.run('rani', format('select public.set_bill(%L, 25000, null)', pg_temp.gid('small')));

do $$ begin
  assert (select ongkir_asked_at is not null and ongkir_set_at is not null and bill_final_at is not null
          from public.groups where id = pg_temp.gid('small')), 'collecting';
  -- 25.000 among the 3 who ordered: 8.300 each, the host 8.400; Nadia ordered nothing and pays nothing.
  assert pg_temp.share('small', 'putri') = 8300 and pg_temp.share('small', 'kevin') = 8300, 'shares round down to Rp 100';
  assert pg_temp.share('small', 'rani') = 8400, 'host takes the remainder';
  assert pg_temp.share('small', 'nadia') = 0 and pg_temp.bill('small', 'nadia') = 0, 'no items, no ongkir';
  assert pg_temp.bill('small', 'putri') = 40300 and pg_temp.bill('small', 'kevin') = 16300 and pg_temp.bill('small', 'rani') = 32400, 'bills';
  assert (select sum(bill_total) from public.group_bill_v where group_id = pg_temp.gid('small')) = 64000 + 25000, 'adds up';
  assert pg_temp.notes('small', 'putri', 'bill_final') = 1 and pg_temp.notes('small', 'nadia', 'bill_final') = 0, 'bill ready notices';
end $$;

-- Putri pays before anything is sent.
select pg_temp.run('putri', format('select public.claim_paid(%L)', pg_temp.gid('small')));
select pg_temp.run('rani', format('select public.confirm_paid(%L, %L)', pg_temp.gid('small'), pg_temp.id('putri')));

-- The ongkir goes up: Putri owes the 1.700 difference.
select pg_temp.run('rani', format('select public.set_bill(%L, 30000, 0)', pg_temp.gid('small')));
do $$ begin
  assert pg_temp.bill('small', 'putri') = 42000, 'putri 42.000';
  assert (select paid_at is null and owed = 1700 and paid_total = 40300 from public.group_bill_v
          where group_id = pg_temp.gid('small') and user_id = pg_temp.id('putri')), 'owes the difference';
end $$;

-- A discount: nobody's bill goes below 0; the host takes the remainder.
select pg_temp.run('rani', format('select public.set_bill(%L, 0, 40000)', pg_temp.gid('small')));
do $$ begin
  -- −40.000 among 3: −13.300 each; Kevin's 8.000 of items stop at 0; the host takes −18.700.
  assert pg_temp.bill('small', 'kevin') = 0, 'kevin floors at 0';
  assert pg_temp.bill('small', 'putri') = 18700, 'putri 18.700';
  assert pg_temp.bill('small', 'rani') = 5300, 'rani takes the remainder';
  assert (select sum(bill_total) from public.group_bill_v where group_id = pg_temp.gid('small')) = 64000 - 40000, 'adds up';
  assert (select paid_at is not null from public.members where group_id = pg_temp.gid('small') and user_id = pg_temp.id('putri')),
    'an earlier payment that covers the new bill counts as paid';
end $$;

-- The discount is capped at items + ongkir; no bill is negative.
select pg_temp.run('rani', format('select public.set_bill(%L, 10000, 90000)', pg_temp.gid('small')));
do $$ begin
  assert (select discount from public.groups where id = pg_temp.gid('small')) = 74000, 'discount capped';
  assert (select min(bill_total) from public.group_bill_v where group_id = pg_temp.gid('small')) >= 0, 'no negative bill';
end $$;
select pg_temp.fails('rani', format('select public.set_bill(%L, 10000000, 0)', pg_temp.gid('small')), 'Amounts can be at most Rp 9.999.999');

-- Back to Atas's real reply; Putri's 40.300 covers it again. Kevin pays; everyone has paid before sending.
select pg_temp.run('rani', format('select public.set_bill(%L, 25000, 0)', pg_temp.gid('small')));
select pg_temp.run('rani', format('select public.confirm_paid(%L, %L)', pg_temp.gid('small'), pg_temp.id('kevin')));
do $$ begin
  assert (select paid_at is not null from public.members where group_id = pg_temp.gid('small') and user_id = pg_temp.id('putri')), 'putri paid';
  assert (select body from public.notifications where group_id = pg_temp.gid('small') and kind = 'everyone_paid'
          order by id desc limit 1) = 'Send the Test small order to Atas before 15:00.', 'pay-first everyone-paid copy';
end $$;

-- Send and confirm: the bills and payments stay as they are.
select pg_temp.run('rani', format('select public.mark_sent(%L)', pg_temp.gid('small')));
select pg_temp.run('rani', format('select public.confirm_atas(%L, 50000, 0)', pg_temp.gid('small')));
do $$ begin
  assert (select state = 'confirmed' and ongkir = 25000 from public.groups where id = pg_temp.gid('small')), 'confirmed, ongkir kept';
  assert pg_temp.bill('small', 'putri') = 40300, 'putri bill unchanged';
  assert (select paid_at is not null from public.members where group_id = pg_temp.gid('small') and user_id = pg_temp.id('putri')),
    'payment before send survives confirm';
  assert (select paid_at is not null from public.members where group_id = pg_temp.gid('small') and user_id = pg_temp.id('kevin')), 'kevin still paid';
end $$;

-- ================================================================ 3 · pay first, Rp 200.000 or more, auto-lock

select pg_temp.mk('big', 'dimas', 'pay_first', array['kevin','putri']);
select pg_temp.add('big', 'kevin', 't-cheesecake', 1), pg_temp.add('big', 'putri', 't-cookies', 1);
select pg_temp.run('kevin', format('select public.share_item(%L, 8, 3)', pg_temp.item('big', 't-cheesecake')));
select pg_temp.run('putri', format('select public.claim_pieces(%L, 2)', pg_temp.item('big', 't-cheesecake')));
-- The host removes Putri, so her claim is released.
select pg_temp.run('dimas', format('select public.remove_member(%L, %L)', pg_temp.gid('big'), pg_temp.id('putri')));
do $$ begin
  assert not exists (select 1 from public.item_claims where group_id = pg_temp.gid('big') and user_id = pg_temp.id('putri')),
    'removed member claims released';
end $$;
update public.groups set cutoff_at = now() - interval '1 minute' where id = pg_temp.gid('big');
select public.tick();
do $$ begin
  -- Cheesecake needed 3 people, had 1 → removed by the auto-lock; subtotal 0 → nothing to pay.
  assert pg_temp.item('big', 't-cheesecake') is null, 'auto-lock applies the minimum too';
  assert (select state from public.groups where id = pg_temp.gid('big')) = 'locked', 'auto-locked';
end $$;

select pg_temp.mk('big2', 'dimas', 'pay_first', array['kevin','putri']);
select pg_temp.add('big2', 'kevin', 't-cheesecake', 1), pg_temp.add('big2', 'putri', 't-cookies', 1);
update public.groups set cutoff_at = now() - interval '1 minute' where id = pg_temp.gid('big2');
select public.tick();
do $$ begin
  assert (select state = 'locked' and bill_final_at is not null and ongkir = 0 from public.groups where id = pg_temp.gid('big2')),
    'final at lock, free ongkir';
  assert pg_temp.bill('big2', 'kevin') = 260000 and pg_temp.bill('big2', 'putri') = 12000, 'item-only bills';
  assert pg_temp.notes('big2', 'kevin', 'bill_final') = 1 and pg_temp.notes('big2', 'kevin', 'locked') = 0, 'bill ready instead of locked';
end $$;
select pg_temp.run('kevin', format('select public.claim_paid(%L)', pg_temp.gid('big2')));
select pg_temp.run('dimas', format('select public.confirm_paid(%L, %L)', pg_temp.gid('big2'), pg_temp.id('kevin')));
select pg_temp.run('dimas', format('select public.mark_sent(%L)', pg_temp.gid('big2')));  -- early send: Putri hasn't paid
select pg_temp.run('dimas', format('select public.confirm_atas(%L, null, null)', pg_temp.gid('big2')));
do $$ begin
  assert (select paid_at is not null from public.members where group_id = pg_temp.gid('big2') and user_id = pg_temp.id('kevin')), 'kevin still paid';
  assert (select owed from public.group_bill_v where group_id = pg_temp.gid('big2') and user_id = pg_temp.id('putri')) = 12000, 'putri owes';
end $$;

-- Deleting groups with shared items and claims (also what account deletion does) must not trip on notices.
delete from public.groups where id in (select v from t_g);

select 'bill.sql: all assertions passed' as result;
rollback;
