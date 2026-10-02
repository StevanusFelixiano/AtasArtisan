-- Demo content for the App Review account (phone 6200000000001, signs in with the review code) and the
-- App Store screenshots. Five demo friends who can't sign in; two groups from the design's sample data.
-- Re-runnable: removes the previous demo first.
do $$
declare
  rani uuid := (select id from public.profiles where phone = '6200000000001');
  ids uuid[] := array[]::uuid[];
  n text; i int := 2; u uuid; g1 uuid; g2 uuid; rani_acct uuid; dimas_acct uuid;
  p record;
begin
  if rani is null then raise exception 'sign the review account in once first'; end if;
  delete from auth.users where email like 'demo-%@wa.ataste.invalid';
  delete from public.groups where host_id = rani;
  delete from public.payout_accounts where user_id = rani;
  delete from public.addresses where user_id = rani;
  update public.profiles set name = 'Rani' where id = rani;

  foreach n in array array['Dimas','Putri','Kevin','Nadia','Arief'] loop
    u := gen_random_uuid();
    insert into auth.users (id, email, aud, role) values (u, 'demo-' || lower(n) || '@wa.ataste.invalid', 'authenticated', 'authenticated');
    insert into public.profiles (id, phone, name) values (u, '620000000000' || i, n);
    ids := ids || u; i := i + 1;
  end loop;

  insert into public.addresses (user_id, label, area, detail, maps_url)
    values (rani, 'Academy Bali', 'Kuta', 'Apple Developer Academy Bali', '');
  insert into public.payout_accounts (user_id, label, account_name, number) values (rani, 'BCA', 'Rani Pratiwi', '5271009934') returning id into rani_acct;
  insert into public.payout_accounts (user_id, label, account_name, number) values (ids[1], 'GoPay', 'Dimas Saputra', '081200000002') returning id into dimas_acct;

  -- Group 1: Rani hosts, open, the design's order.
  insert into public.groups (host_id, name, area, address_label, address_detail, delivery_at, cutoff_at, payout_account_id)
    values (rani, 'Academy Bali Friday Treats', 'Kuta', 'Academy Bali', 'Apple Developer Academy Bali',
            date_trunc('day', now() at time zone 'Asia/Makassar') at time zone 'Asia/Makassar' + interval '2 days 10 hours',
            date_trunc('day', now() at time zone 'Asia/Makassar') at time zone 'Asia/Makassar' + interval '1 day 13 hours',
            rani_acct) returning id into g1;
  insert into public.members (group_id, user_id) select g1, unnest(ids);
  for p in select * from (values
      (rani, 'Butter Croissant', 2, '{"Berat":"90gr"}'::jsonb, ''),
      (rani, 'Classic Sourdough', 1, '{"Berat":"1000gr","Slice":"Sliced 15mm"}', ''),
      (rani, 'Burnt Cheesecake 20 cm', 1, '{"Slice":"Unsliced"}', ''),
      (ids[1], 'Pain Au Chocolate', 1, '{"Berat":"80gr"}', ''),
      (ids[1], 'Cinnamon Roll 60 gr', 2, '{}', ''),
      (ids[2], 'Pain Au Chocolate', 2, '{"Berat":"80gr"}', 'warm it up if you can'),
      (ids[3], 'Brioche Bun', 1, '{"Berat":"80gr"}', ''),
      (ids[3], 'English Muffin', 1, '{"Berat":"80gr"}', ''),
      (ids[3], 'Pretzel 120 gr', 1, '{}', ''),
      (ids[4], 'Banana Cake', 1, '{"Berat":"600gr"}', ''),
      (ids[5], 'Cookies 100 gr', 2, '{"Rasa":"Chocolate"}', '')) as t(owner, pname, qty, opts, note)
  loop
    insert into public.items (group_id, owner_id, product_id, options, qty, note)
      select g1, p.owner, pr.id, p.opts, p.qty, p.note from public.products pr where pr.name = p.pname;
  end loop;
  -- Rani shares her cheesecake in 12 pieces; Putri and Kevin claim 3 each.
  update public.items set share_pieces = 12 where group_id = g1 and name = 'Burnt Cheesecake 20 cm';
  insert into public.item_claims (item_id, group_id, user_id, pieces)
    select it.id, g1, x, 3 from public.items it, unnest(array[ids[2], ids[3]]) x
    where it.group_id = g1 and it.name = 'Burnt Cheesecake 20 cm';

  -- Group 2: Dimas hosts, Atas confirmed, Rani owes him.
  insert into public.groups (host_id, name, area, address_label, address_detail, delivery_at, payout_account_id, state, sent_at)
    values (ids[1], 'Academy Bali Snacks', 'Kuta', 'Academy Bali', 'Apple Developer Academy Bali',
            date_trunc('day', now() at time zone 'Asia/Makassar') at time zone 'Asia/Makassar' + interval '1 day 10 hours',
            dimas_acct, 'sent', now()) returning id into g2;
  insert into public.members (group_id, user_id) values (g2, rani), (g2, ids[4]);
  insert into public.items (group_id, owner_id, product_id, options, qty)
    select g2, x.owner, pr.id, x.opts, x.qty from (values
      (rani, 'Almond Croissant', '{"Berat":"90gr"}'::jsonb, 2), (ids[1], 'Focaccia', '{"Berat":"1000gr"}', 1),
      (ids[4], 'Classic Brownie 20x20 cm', '{}', 1)) as x(owner, pname, opts, qty)
    join public.products pr on pr.name = x.pname;
  -- confirm_atas as Dimas would, so bills freeze and Rani gets her notification
  perform set_config('request.jwt.claims', json_build_object('sub', ids[1], 'role', 'authenticated')::text, true);
  perform public.confirm_atas(g2, 30000, 15000);
end $$;
