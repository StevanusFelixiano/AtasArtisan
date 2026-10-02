-- Photos, push, and the minute timer.

-- ---------------------------------------------------------------- storage
-- Private buckets; the path is the record (GoodMinton's payment-proofs pattern).
--   receipts: <group>/<user>.jpg   readable by that member and the host
--   delivery: <group>/<uuid>.jpg   readable by the group
--   legal:    public PDFs (privacy, terms, support)

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('receipts', 'receipts', false, 2097152, array['image/jpeg']),
  ('delivery', 'delivery', false, 2097152, array['image/jpeg']),
  ('legal', 'legal', true, 5242880, array['application/pdf'])
on conflict (id) do nothing;

-- Null for anything that isn't one of ours: a cast that raised here would break every bucket.
create function public.path_group(name text) returns uuid language sql immutable parallel safe as $$
  select (regexp_match(name, '^([0-9a-f-]{36})/[0-9a-f-]{36}\.jpg$'))[1]::uuid
$$;
create function public.path_file(name text) returns uuid language sql immutable parallel safe as $$
  select (regexp_match(name, '^[0-9a-f-]{36}/([0-9a-f-]{36})\.jpg$'))[1]::uuid
$$;

create policy receipt_send on storage.objects for insert to authenticated with check (
  bucket_id = 'receipts' and public.path_file(name) = (select auth.uid()) and public.is_member(public.path_group(name)));
create policy receipt_replace on storage.objects for update to authenticated
  using (bucket_id = 'receipts' and public.path_file(name) = (select auth.uid()) and public.is_member(public.path_group(name)))
  with check (bucket_id = 'receipts' and public.path_file(name) = (select auth.uid()) and public.is_member(public.path_group(name)));
create policy receipt_read on storage.objects for select to authenticated using (
  bucket_id = 'receipts' and (public.path_file(name) = (select auth.uid()) or public.is_host(public.path_group(name))));

create policy delivery_send on storage.objects for insert to authenticated with check (
  bucket_id = 'delivery' and public.is_member(public.path_group(name)));
create policy delivery_read on storage.objects for select to authenticated using (
  bucket_id = 'delivery' and public.is_member(public.path_group(name)));

-- ---------------------------------------------------------------- push
-- Every notifications row is pushed by the `push` function. The trigger's secret header is the
-- only way in; no user JWT reaches the function.

create extension if not exists pg_net with schema extensions;

select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'push_hook_secret');

create function public.push_notification() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform net.http_post(
    url := 'https://scgyssmzfurqjkgfomtq.supabase.co/functions/v1/push',
    body := jsonb_build_object('id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-push-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'push_hook_secret')));
  return new;
end $$;
revoke execute on function public.push_notification() from public, anon, authenticated;
create trigger push_notification after insert on public.notifications
  for each row execute function public.push_notification();

-- ---------------------------------------------------------------- minute timer

create extension if not exists pg_cron;
select cron.schedule('ataste-tick', '* * * * *', 'select public.tick()');
