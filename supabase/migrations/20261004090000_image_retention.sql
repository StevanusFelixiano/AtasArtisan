-- Receipts and delivery photos are kept for a week. SQL can't delete storage objects (storage.protect_delete),
-- so a daily cron calls the sweep function, which lists them here and removes them through the Storage API.
create or replace function public.expired_images() returns table (bucket_id text, name text)
language sql stable security definer set search_path = '' as $$
  select o.bucket_id, o.name from storage.objects o
  where o.bucket_id in ('receipts', 'delivery') and coalesce(o.updated_at, o.created_at) < now() - interval '7 days'
$$;
revoke execute on function public.expired_images() from public, anon, authenticated;
grant execute on function public.expired_images() to service_role;

-- 03:00 WITA
select cron.schedule('ataste-sweep', '0 19 * * *', $$
  select net.http_post(
    url := 'https://scgyssmzfurqjkgfomtq.supabase.co/functions/v1/sweep',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-push-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'push_hook_secret')))
$$);
