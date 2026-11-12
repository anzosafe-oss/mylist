create table public.mylist_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 alias text not null check(alias=btrim(alias) and char_length(alias) between 1 and 30),
 color text not null default 'blue' check(color in ('blue','purple','pink','teal','orange','cyan','gold','red','slate'))
);
alter table public.mylist_profiles enable row level security;
revoke all on public.mylist_profiles from anon;
grant select,insert,update on public.mylist_profiles to authenticated;
create policy profiles_read on public.mylist_profiles for select to authenticated using(mylist_private.allowed());
create policy profiles_insert_own on public.mylist_profiles for insert to authenticated with check(user_id=(select auth.uid()) and mylist_private.allowed());
create policy profiles_update_own on public.mylist_profiles for update to authenticated using(user_id=(select auth.uid()) and mylist_private.allowed()) with check(user_id=(select auth.uid()) and mylist_private.allowed());