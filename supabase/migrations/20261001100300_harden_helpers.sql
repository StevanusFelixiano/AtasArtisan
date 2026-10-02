-- Advisor: pin search_path on the plain helpers; Supabase's rls_auto_enable() must not be an RPC.
alter function public.is_delivery_area(text) set search_path = '';
alter function public.rp(int) set search_path = '';
alter function public.lock_body(public.groups) set search_path = '';
alter function public.path_group(text) set search_path = '';
alter function public.path_file(text) set search_path = '';
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
