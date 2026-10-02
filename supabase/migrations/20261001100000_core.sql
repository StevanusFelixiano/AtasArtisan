-- Ataste core schema. SwiftUI talks to these tables directly; RLS is the boundary.
-- Columns that move an order through its states are not granted to clients: those change only
-- through the security-definer functions in 20261001100100_logic.sql.

create extension if not exists pgcrypto with schema extensions;

-- Vault reader for edge functions (service role only).
create function public.secret(name text) returns text language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where decrypted_secrets.name = secret.name
$$;
revoke execute on function public.secret(text) from public, anon, authenticated;
grant execute on function public.secret(text) to service_role;

-- ---------------------------------------------------------------- people

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  phone text not null unique check (phone ~ '^[0-9]{8,15}$'),
  name text not null default '' check (length(name) <= 60),
  msg_lang text not null default 'id' check (msg_lang in ('id', 'en')),
  notify_mute text[] not null default '{}',
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
revoke insert, update, delete on public.profiles from anon, authenticated;
grant update (name, msg_lang, notify_mute) on public.profiles to authenticated;

-- Where Atas delivers (atasartisan.com popup, 2026-10-01).
create function public.is_delivery_area(a text) returns boolean language sql immutable parallel safe as $$
  select a = any (array['Denpasar','Canggu','Tabanan','Kerobokan','Pererenan','Seminyak','Kuta','Uluwatu',
                        'Jimbaran','Nusa Dua','Ubud','Sanur','Nusa Penida','Nusa Lembongan'])
$$;

create table public.addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  label text not null check (length(label) between 1 and 40),
  area text not null check (public.is_delivery_area(area)),
  detail text not null default '' check (length(detail) <= 200),
  maps_url text not null default '' check (maps_url = '' or maps_url ~ '^https://'),
  created_at timestamptz not null default now()
);
alter table public.addresses enable row level security;
create policy own on public.addresses for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table public.payout_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  label text not null check (length(label) between 1 and 30),          -- BCA, GoPay, ...
  account_name text not null check (length(account_name) between 1 and 60),
  number text not null check (length(number) between 3 and 30),
  created_at timestamptz not null default now()
);
alter table public.payout_accounts enable row level security;
create policy own on public.payout_accounts for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------- groups

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default upper(substr(translate(encode(extensions.gen_random_bytes(8), 'base64'), '+/=0O1Il', ''), 1, 6)),
  host_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null check (length(name) between 1 and 60),
  personal boolean not null default false,
  area text not null check (public.is_delivery_area(area)),
  address_label text not null default '',
  address_detail text not null default '',
  maps_url text not null default '',
  delivery_at timestamptz not null,
  cutoff_at timestamptz,
  pay_rule text not null default 'order_first' check (pay_rule in ('order_first', 'pay_first')),
  msg_lang text not null default 'id' check (msg_lang in ('id', 'en')),
  payout_account_id uuid references public.payout_accounts on delete set null,
  state text not null default 'open'
    check (state in ('open', 'locked', 'edits', 'sent', 'confirmed', 'delivered', 'closed', 'cancelled')),
  ongkir int check (ongkir >= 0),
  discount int check (discount >= 0),
  cutoff_reminded boolean not null default false,
  discount_notified boolean not null default false,
  created_at timestamptz not null default now(),
  locked_at timestamptz, sent_at timestamptz, confirmed_at timestamptz,
  delivered_at timestamptz, closed_at timestamptz, cancelled_at timestamptz
);
alter table public.groups enable row level security;
revoke insert, update, delete on public.groups from anon, authenticated;
grant insert (name, personal, area, address_label, address_detail, maps_url, delivery_at, cutoff_at, pay_rule, msg_lang, payout_account_id)
  on public.groups to authenticated;
grant update (name, area, address_label, address_detail, maps_url, delivery_at, cutoff_at, pay_rule, msg_lang, payout_account_id)
  on public.groups to authenticated;

create table public.members (
  group_id uuid not null references public.groups on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  joined_at timestamptz not null default now(),
  removed_at timestamptz,
  done_editing_at timestamptz,
  proof_at timestamptz,      -- the member says they paid (receipt uploaded)
  paid_at timestamptz,       -- the host confirmed it
  nudged_at timestamptz,
  bill_total int,            -- frozen when Atas confirms
  primary key (group_id, user_id)
);
alter table public.members enable row level security;
revoke insert, update, delete on public.members from anon, authenticated;
create index on public.members (user_id);

-- Membership helpers: security definer so policies on members don't recurse into members.
create function public.is_member(g uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.members m
                 where m.group_id = g and m.user_id = (select auth.uid()) and m.removed_at is null)
$$;
create function public.is_host(g uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.groups x where x.id = g and x.host_id = (select auth.uid()))
$$;
create function public.shares_group(other uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.members a join public.members b on a.group_id = b.group_id
                 where a.user_id = (select auth.uid()) and b.user_id = other
                   and a.removed_at is null)
$$;
revoke execute on function public.is_member(uuid), public.is_host(uuid), public.shares_group(uuid) from public, anon;
grant execute on function public.is_member(uuid), public.is_host(uuid), public.shares_group(uuid) to authenticated;

create policy members_read on public.groups for select to authenticated using (public.is_member(id) or host_id = (select auth.uid()));
create policy host_creates on public.groups for insert to authenticated with check (host_id = (select auth.uid()));
create policy host_edits on public.groups for update to authenticated
  using (host_id = (select auth.uid()) and state in ('open', 'locked', 'edits'))
  with check (host_id = (select auth.uid()));

create policy co_members on public.members for select to authenticated using (public.is_member(group_id) or user_id = (select auth.uid()));

-- People see themselves and whoever they order with (name + phone: the host messages members on WhatsApp).
create policy self_and_co on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.shares_group(id));
create policy self_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Members see where to pay the host.
create policy host_account_visible on public.payout_accounts for select to authenticated
  using (exists (select 1 from public.groups g where g.payout_account_id = payout_accounts.id and public.is_member(g.id)));

-- The host is a member of their own group.
create function public.add_host_member() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.members (group_id, user_id) values (new.id, new.host_id);
  return new;
end $$;
revoke execute on function public.add_host_member() from public, anon, authenticated;
create trigger add_host_member after insert on public.groups for each row execute function public.add_host_member();

-- ---------------------------------------------------------------- menu (written by menu-ingest only)

create table public.collections (
  id text primary key,
  name text not null,
  sort int not null default 0
);
create table public.products (
  id text primary key,                     -- Atas/iSeller product id
  collection_id text references public.collections on delete set null,
  name text not null,
  description text not null default '',
  photo_url text not null default '',
  base_price int not null check (base_price >= 0),
  -- [{"name":"Berat","choices":["600gr","1000gr"]}, ...]
  option_groups jsonb not null default '[]',
  -- [{"options":{"Berat":"600gr","Slice":"Sliced 15mm"},"price":21000,"available":true}, ...]
  variants jsonb not null default '[]',
  available boolean not null default true,
  sort int not null default 0,
  updated_at timestamptz not null default now()
);
create table public.menu_meta (
  id boolean primary key default true check (id),
  synced_at timestamptz not null default now()
);
alter table public.collections enable row level security;
alter table public.products enable row level security;
alter table public.menu_meta enable row level security;
create policy read on public.collections for select to authenticated using (true);
create policy read on public.products for select to authenticated using (true);
create policy read on public.menu_meta for select to authenticated using (true);

-- ---------------------------------------------------------------- items and splits

create table public.items (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups on delete cascade,
  owner_id uuid not null default auth.uid() references auth.users on delete cascade,
  product_id text not null references public.products on delete restrict,
  name text not null default '',             -- snapshot, set by price_item()
  options jsonb not null default '{}',       -- {"Berat":"1000gr","Slice":"Sliced 15mm"}
  unit_price int not null default 0,         -- set by price_item(), never by the client
  qty int not null default 1 check (qty between 1 and 50),
  note text not null default '' check (length(note) <= 140),
  flag_reason text,
  flagged_at timestamptz,
  soldout_notified boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.items enable row level security;
revoke insert, update, delete on public.items from anon, authenticated;
grant insert (group_id, product_id, options, qty, note) on public.items to authenticated;
grant update (product_id, options, qty, note) on public.items to authenticated;
grant delete on public.items to authenticated;
create index on public.items (group_id);

-- A member may change their items while the group is open, or during an edit round if the host
-- flagged one of theirs.
create function public.can_edit_items(g uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.groups x where x.id = g and (
           x.state = 'open'
           or (x.state = 'edits' and exists (select 1 from public.items i
                where i.group_id = g and i.owner_id = (select auth.uid()) and i.flagged_at is not null))))
$$;
revoke execute on function public.can_edit_items(uuid) from public, anon;
grant execute on function public.can_edit_items(uuid) to authenticated;

create policy members_read on public.items for select to authenticated using (public.is_member(group_id));
create policy owner_adds on public.items for insert to authenticated
  with check (owner_id = (select auth.uid()) and public.is_member(group_id) and public.can_edit_items(group_id));
create policy owner_edits on public.items for update to authenticated
  using (owner_id = (select auth.uid()) and public.can_edit_items(group_id))
  with check (owner_id = (select auth.uid()));
create policy owner_removes on public.items for delete to authenticated
  using (owner_id = (select auth.uid()) and public.can_edit_items(group_id));

-- Price and name come from the menu, so a member can't type their own price.
create function public.price_item() returns trigger language plpgsql security definer set search_path = '' as $$
declare p public.products; v jsonb;
begin
  select * into p from public.products where id = new.product_id;
  if p.id is null then raise exception 'unknown product'; end if;
  new.name := p.name;
  new.unit_price := p.base_price;
  if jsonb_array_length(p.variants) > 0 then
    select x into v from jsonb_array_elements(p.variants) x where x->'options' = new.options limit 1;
    if v is null then raise exception 'choose all options for %', p.name; end if;
    new.unit_price := (v->>'price')::int;
  end if;
  return new;
end $$;
revoke execute on function public.price_item() from public, anon, authenticated;
create trigger price_item before insert or update of product_id, options on public.items
  for each row execute function public.price_item();

create table public.splits (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items on delete cascade,
  proposer_id uuid not null references auth.users on delete cascade,
  state text not null default 'pending' check (state in ('pending', 'accepted', 'declined', 'cancelled')),
  created_at timestamptz not null default now()
);
create unique index one_live_split on public.splits (item_id) where state in ('pending', 'accepted');
create table public.split_shares (
  split_id uuid not null references public.splits on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  pct numeric(5, 2) not null check (pct > 0 and pct <= 100),
  accepted_at timestamptz,
  primary key (split_id, user_id)
);
alter table public.splits enable row level security;
alter table public.split_shares enable row level security;
revoke insert, update, delete on public.splits, public.split_shares from anon, authenticated;
create policy members_read on public.splits for select to authenticated
  using (exists (select 1 from public.items i where i.id = item_id and public.is_member(i.group_id)));
create policy members_read on public.split_shares for select to authenticated
  using (exists (select 1 from public.splits s join public.items i on i.id = s.item_id
                 where s.id = split_id and public.is_member(i.group_id)));

create table public.delivery_proofs (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups on delete cascade,
  path text not null,
  by_user uuid not null references auth.users on delete cascade,
  hidden boolean not null default false,
  reported_by uuid references auth.users on delete set null,
  created_at timestamptz not null default now()
);
alter table public.delivery_proofs enable row level security;
revoke insert, update, delete on public.delivery_proofs from anon, authenticated;
create policy members_read on public.delivery_proofs for select to authenticated using (public.is_member(group_id));

-- ---------------------------------------------------------------- devices and notifications

create table public.devices (
  token text primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  env text not null check (env in ('sandbox', 'production')),
  updated_at timestamptz not null default now()
);
alter table public.devices enable row level security;
create policy own on public.devices for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create table public.notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users on delete cascade,
  group_id uuid references public.groups on delete cascade,
  kind text not null,
  title text not null,
  body text not null,
  created_at timestamptz not null default now()
);
alter table public.notifications enable row level security;
revoke insert, update, delete on public.notifications from anon, authenticated;
create policy own on public.notifications for select to authenticated using (user_id = (select auth.uid()));
create index on public.notifications (user_id, created_at desc);

create table public.apns_jwt (
  id boolean primary key default true check (id),
  token text not null,
  issued_at timestamptz not null
);
alter table public.apns_jwt enable row level security;

-- ---------------------------------------------------------------- reverse-OTP codes (service role only)

create table public.wa_codes (
  code text primary key,                 -- the 4 characters after "ATASTE "
  nonce text not null unique,            -- held by the waiting app
  ip text not null default '',
  phone text,
  push_name text,
  wa_id text unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '10 minutes',
  verified_at timestamptz,
  consumed_at timestamptz
);
alter table public.wa_codes enable row level security;
