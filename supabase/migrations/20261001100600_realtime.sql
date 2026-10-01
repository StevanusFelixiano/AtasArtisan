-- The group screen refetches on any change to its rows; deletes must carry the old row (iOS guide).
alter publication supabase_realtime add table public.groups, public.members, public.items, public.splits, public.split_shares, public.delivery_proofs;
alter table public.items replica identity full;
alter table public.members replica identity full;
alter table public.splits replica identity full;
alter table public.split_shares replica identity full;
