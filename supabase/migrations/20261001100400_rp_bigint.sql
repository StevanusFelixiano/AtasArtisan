-- group_bill_v's delivery_share is bigint (it divides by a count); rp() takes bigint so int and bigint both fit.
drop function public.rp(int);
create function public.rp(n bigint) returns text language sql immutable set search_path = '' as $$
  select 'Rp ' || replace(to_char(n, 'FM999,999,999'), ',', '.')
$$;
revoke execute on function public.rp(bigint) from public, anon, authenticated;
