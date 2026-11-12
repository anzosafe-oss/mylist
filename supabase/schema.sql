begin;
create schema if not exists mylist_private;
revoke all on schema mylist_private from public,anon;
grant usage on schema mylist_private to authenticated;
create table public.mylist_accounts(email text primary key check(email=lower(email)),user_id uuid unique references auth.users(id),is_admin boolean not null default false,invited_at timestamptz not null default now(),accepted_at timestamptz);
alter table public.mylist_accounts enable row level security;
create table public.mylist_lists(id uuid primary key default gen_random_uuid(),owner_id uuid not null references auth.users(id),name text not null check(length(name) between 1 and 60),store text not null default 'custom',completed_at timestamptz,deleted_at timestamptz,created_at timestamptz not null default now());
alter table public.mylist_lists enable row level security;
create table public.mylist_members(list_id uuid references public.mylist_lists(id) on delete cascade,user_id uuid references auth.users(id),primary key(list_id,user_id));
alter table public.mylist_members enable row level security;
create index mylist_members_user on public.mylist_members(user_id);
create table public.mylist_items(id uuid primary key default gen_random_uuid(),list_id uuid not null references public.mylist_lists(id) on delete cascade,name text not null check(length(name) between 1 and 160),quantity numeric not null default 1 check(quantity>0 and quantity<=1000000),unit text not null default 'buc.' check(length(unit) between 1 and 30),important boolean not null default false,done boolean not null default false,position numeric not null default 0);
alter table public.mylist_items enable row level security;
create index mylist_items_list on public.mylist_items(list_id);
create function mylist_private.allowed() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.mylist_accounts where user_id=auth.uid() and accepted_at is not null)$$;
create function mylist_private.is_admin() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.mylist_accounts where user_id=auth.uid() and is_admin and accepted_at is not null)$$;
create function mylist_private.access_list(lid uuid) returns boolean language sql stable security definer set search_path='' as $$select mylist_private.allowed() and exists(select 1 from public.mylist_lists l where l.id=lid and l.deleted_at is null and(l.owner_id=auth.uid() or exists(select 1 from public.mylist_members m where m.list_id=lid and m.user_id=auth.uid())))$$;
revoke all on all functions in schema mylist_private from public,anon;
grant execute on all functions in schema mylist_private to authenticated;
create policy account_read on public.mylist_accounts for select to authenticated using(user_id=(select auth.uid()) or email=lower((select auth.jwt()->>'email')) or (mylist_private.allowed() and accepted_at is not null));
create policy account_invite on public.mylist_accounts for insert to authenticated with check(mylist_private.is_admin() and not is_admin and user_id is null and accepted_at is null);
create policy list_read on public.mylist_lists for select to authenticated using(mylist_private.access_list(id));
create policy member_read on public.mylist_members for select to authenticated using(mylist_private.access_list(list_id));
create policy item_read on public.mylist_items for select to authenticated using(mylist_private.access_list(list_id));
grant select on public.mylist_accounts,public.mylist_lists,public.mylist_members,public.mylist_items to authenticated;
grant insert(email) on public.mylist_accounts to authenticated;
create function mylist_private.action(op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); lid uuid; iid uuid; own uuid; rec record; target uuid; k text; result jsonb:='{}';
begin
 if uid is null then raise exception 'Autentificare necesară'; end if;
 if op='accept' then
  update public.mylist_accounts a set user_id=uid,accepted_at=coalesce(a.accepted_at,now()) where a.email=lower(auth.jwt()->>'email') and(a.user_id is null or a.user_id=uid) and exists(select 1 from auth.users u where u.id=uid and u.email_confirmed_at is not null);
 end if;
 if not mylist_private.allowed() then raise exception 'Ai nevoie de o invitație pentru MyList';end if;
 if op='accept' then return '{}';end if;
 if op='create' then insert into public.mylist_lists(owner_id,name,store) values(uid,trim(p->>'name'),coalesce(p->>'store','custom')) returning id into lid; return jsonb_build_object('id',lid);end if;
 if op='cancel_invite' then
  if not mylist_private.is_admin() then raise exception 'Doar administratorul';end if;
  delete from public.mylist_accounts where email=lower(p->>'email') and user_id is null and not is_admin;return '{}';
 end if;
 lid:=(p->>'list_id')::uuid;
 select owner_id into own from public.mylist_lists where id=lid and deleted_at is null for update;
 if own is null or not mylist_private.access_list(lid) then raise exception 'Lista nu este disponibilă';end if;
 if op in('rename','delete','share','revoke') and own<>uid then raise exception 'Doar proprietarul listei';end if;
 if op='rename' then update public.mylist_lists set name=trim(p->>'name') where id=lid;
 elsif op='delete' then update public.mylist_lists set deleted_at=now() where id=lid;
 elsif op='share' then
  target:=(p->>'user_id')::uuid;
  if target=own or not exists(select 1 from public.mylist_accounts where user_id=target and accepted_at is not null) then raise exception 'Cont indisponibil';end if;
  insert into public.mylist_members values(lid,target) on conflict do nothing;
 elsif op='revoke' then delete from public.mylist_members where list_id=lid and user_id=(p->>'user_id')::uuid;
 elsif op='restore' then update public.mylist_items set done=false where list_id=lid;update public.mylist_lists set completed_at=null where id=lid;
 else
  if exists(select 1 from public.mylist_lists where id=lid and completed_at is not null) then raise exception 'Restaurează lista înainte de editare';end if;
  if op='add' then
   if not exists(select 1 from public.mylist_items where list_id=lid and lower(name)=lower(trim(p->>'name')) and not done) then
    insert into public.mylist_items(list_id,name,quantity,unit,position,important) values(lid,trim(p->>'name'),(p->>'quantity')::numeric,p->>'unit',(select coalesce(max(position),0)+1024 from public.mylist_items where list_id=lid),coalesce((p->>'important')::boolean,false));
   else raise exception 'Produsul este deja pe listă';end if;
  elsif op='edit' then
   iid:=(p->>'id')::uuid;
   update public.mylist_items set name=case when p?'name' then trim(p->>'name') else name end,quantity=case when p?'quantity' then(p->>'quantity')::numeric else quantity end,unit=case when p?'unit' then p->>'unit' else unit end,done=case when p?'done' then(p->>'done')::boolean else done end,important=case when p?'important' then(p->>'important')::boolean else important end where id=iid and list_id=lid;
  elsif op='remove' then delete from public.mylist_items where id=(p->>'id')::uuid and list_id=lid;
  elsif op='reorder' then
   for rec in select value,ordinality from jsonb_array_elements_text(p->'ids') with ordinality loop
    update public.mylist_items set position=rec.ordinality*1024 where id=rec.value::uuid and list_id=lid;
   end loop;
  else raise exception 'Operație necunoscută';end if;
  if exists(select 1 from public.mylist_items where list_id=lid) and not exists(select 1 from public.mylist_items where list_id=lid and not done) then update public.mylist_lists set completed_at=now() where id=lid;end if;
 end if;
 return result;
end$$;
revoke all on function mylist_private.action(text,jsonb) from public,anon;
grant execute on function mylist_private.action(text,jsonb) to authenticated;
create function public.mylist_action(op text,p jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select mylist_private.action(op,p)$$;
revoke all on function public.mylist_action(text,jsonb) from public,anon;
grant execute on function public.mylist_action(text,jsonb) to authenticated;
-- Bootstrap an administrator privately after verifying the account.
-- Do not commit personal email addresses or user IDs into this file.
commit;
