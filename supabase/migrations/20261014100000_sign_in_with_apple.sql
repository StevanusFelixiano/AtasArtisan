-- Sign in with Apple (App Review 4.8). Apple is the only sign-in; the reverse WhatsApp code now only verifies a
-- number. Verified = `profiles.phone is not null`: it earns the badge and is needed to host (members pay the host,
-- and Atas needs the host's number in the order message).

-- A new Apple account has no number until it verifies one. Unique and the format check stay.
alter table public.profiles alter column phone drop not null;

-- Which Apple ID signs in to which account. The `apple` function writes it; `account` revokes the refresh token on
-- deletion (guideline 5.1.1(v)). Service role only.
create table public.apple_accounts (
  user_id uuid primary key references auth.users on delete cascade,
  sub text not null unique,              -- Apple's stable user id for this app
  refresh_token text,                    -- from the authorization code; null when Apple's exchange failed
  created_at timestamptz not null default now()
);
alter table public.apple_accounts enable row level security;
revoke all on public.apple_accounts from anon, authenticated;

-- A code started by a signed-in user verifies that user's number (null: the old sign-in mode, builds 23 and older).
alter table public.wa_codes add column user_id uuid references auth.users on delete cascade;

-- 9-8: whether the caller's account can sign in with Apple.
create function public.apple_linked() returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(exists (select 1 from public.apple_accounts a where a.user_id = (select auth.uid())), false)
$$;
revoke execute on function public.apple_linked() from public, anon;
grant execute on function public.apple_linked() to authenticated;

-- Hosting gate (9-6): only a verified number can create a group, a personal order included (Atas needs the number).
drop policy host_creates on public.groups;
create policy host_creates on public.groups for insert to authenticated
  with check (host_id = (select auth.uid())
              and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.phone is not null));
