-- MyList families: four seats INCLUDING the family administrator.
create table public.mylist_families(id uuid primary key default gen_random_uuid(),name text not null default 'Familia mea',owner_email text not null unique,admin_id uuid references auth.users(id),created_at timestamptz not null default now(),max_members integer not null default 4 check(max_members=4));
alter table public.mylist_families enable row level security;
alter table public.mylist_accounts add column family_id uuid references public.mylist_families(id),add column invited_by uuid references auth.users(id);
-- Preserve the existing four-person household and every existing list/share.
do $$declare f uuid; a record;begin
 select * into a from public.mylist_accounts where is_admin order by invited_at limit 1;
 if a.email is not null then
  if (select count(*) from public.mylist_accounts)>4 then raise exception 'Migration requires explicit household mapping';end if;
  insert into public.mylist_families(owner_email,admin_id) values(a.email,a.user_id) returning id into f;
  update public.mylist_accounts set family_id=f,invited_by=case when email<>a.email then a.user_id else null end;
 end if;
end$$;
alter table public.mylist_accounts alter column family_id set not null;
create index mylist_accounts_family on public.mylist_accounts(family_id);
create table public.mylist_invitations(id uuid primary key default gen_random_uuid(),family_id uuid not null references public.mylist_families(id),email text not null check(email=lower(email)),invited_by uuid references auth.users(id),kind text not null check(kind in('family','administrator')),status text not null default 'pending' check(status in('pending','accepted','cancelled','failed')),created_at timestamptz not null default now(),sent_at timestamptz,accepted_at timestamptz,send_count integer not null default 0,delivery_key uuid,delivery_started_at timestamptz);
alter table public.mylist_invitations enable row level security;
create index mylist_invitation_family on public.mylist_invitations(family_id);
create unique index mylist_invitation_pending_email on public.mylist_invitations(email) where status='pending';
insert into public.mylist_invitations(family_id,email,invited_by,kind,status,created_at,sent_at,accepted_at,send_count) select family_id,email,invited_by,'family',case when accepted_at is null then 'pending' else 'accepted' end,invited_at,invited_at,accepted_at,1 from public.mylist_accounts where invited_by is not null;
create function mylist_private.family_id() returns uuid language sql stable security definer set search_path='' as $$select family_id from public.mylist_accounts where user_id=auth.uid() and accepted_at is not null$$;
create function mylist_private.family_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.mylist_families where id=mylist_private.family_id() and admin_id=auth.uid())$$;
drop policy account_read on public.mylist_accounts;
drop policy account_invite on public.mylist_accounts;
revoke insert on public.mylist_accounts from authenticated;
revoke insert(email) on public.mylist_accounts from authenticated;
create policy account_read on public.mylist_accounts for select to authenticated using(user_id=(select auth.uid()) or (mylist_private.allowed() and family_id=(select mylist_private.family_id())));
create policy family_read on public.mylist_families for select to authenticated using(id=(select mylist_private.family_id()));
create policy invitation_read on public.mylist_invitations for select to authenticated using(family_id=(select mylist_private.family_id()) and (select mylist_private.family_admin()));
drop policy profiles_read on public.mylist_profiles;
create policy profiles_read on public.mylist_profiles for select to authenticated using(mylist_private.allowed() and exists(select 1 from public.mylist_accounts a where a.user_id=mylist_profiles.user_id and a.accepted_at is not null and a.family_id=(select mylist_private.family_id())));
grant select on public.mylist_families,public.mylist_invitations to authenticated;
-- Keep list operations unchanged, but put family authorization in front of them.
alter function mylist_private.action(text,jsonb) rename to list_action_v1;
revoke all on function mylist_private.list_action_v1(text,jsonb) from authenticated,public,anon;
create function mylist_private.action(op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();a record;f uuid;target uuid;begin
 if uid is null then raise exception 'Autentificare necesară';end if;
 if op='accept' then
  -- Lock the household BEFORE accepting its reserved seat; cancellation uses the same lock.
  select family_id into f from public.mylist_accounts where email=lower(auth.jwt()->>'email');
  perform 1 from public.mylist_families where id=f for update;
  update public.mylist_accounts set user_id=uid,accepted_at=coalesce(accepted_at,now()) where email=lower(auth.jwt()->>'email') and(user_id is null or user_id=uid) and exists(select 1 from auth.users where id=uid and email_confirmed_at is not null);
  if not mylist_private.allowed() then raise exception 'Ai nevoie de o invitație pentru MyList';end if;
  update public.mylist_families set admin_id=uid where id=f and owner_email=lower(auth.jwt()->>'email') and admin_id is null;
  update public.mylist_invitations set status='accepted',accepted_at=coalesce(accepted_at,now()) where email=lower(auth.jwt()->>'email') and status='pending' and family_id=f;
  return '{}';
 end if;
 if not mylist_private.allowed() then raise exception 'Acces indisponibil';end if;
 if op='cancel_invite' then
  select family_id into f from public.mylist_accounts where email=lower(trim(p->>'email'));
  perform 1 from public.mylist_families where id=f for update;
  if not mylist_private.is_admin() and not(mylist_private.family_admin() and f=mylist_private.family_id()) then raise exception 'Doar administratorul familiei';end if;
  select * into a from public.mylist_accounts where email=lower(trim(p->>'email')) for update;
  if not found or a.accepted_at is not null then raise exception 'Invitația nu mai este în așteptare';end if;
  delete from public.mylist_accounts where email=a.email and not is_admin;
  update public.mylist_invitations set status='cancelled',delivery_key=null where email=a.email and status='pending';return '{}';
 end if;
 if op='remove_account' then
  if not mylist_private.is_admin() then raise exception 'Doar administratorul MyList poate șterge conturi';end if;
  select * into a from public.mylist_accounts where email=lower(trim(p->>'email'));
  perform 1 from public.mylist_families where id=a.family_id for update;
  if exists(select 1 from public.mylist_families where admin_id=a.user_id and id=a.family_id) then raise exception 'Administratorul familiei este protejat. Retrage mai întâi invitațiile familiei și contactează administratorul MyList.';end if;
  update public.mylist_invitations set status='cancelled',delivery_key=null where email=a.email and status in('pending','accepted');
  return mylist_private.list_action_v1(op,p);
 end if;
 if op='share' then
  target:=(p->>'user_id')::uuid;
  if not exists(select 1 from public.mylist_accounts where user_id=target and accepted_at is not null and family_id=mylist_private.family_id()) then raise exception 'Poți distribui lista doar membrilor familiei tale';end if;
 end if;
 return mylist_private.list_action_v1(op,p);
end$$;
-- Global dashboard exposes account administration, never private shopping-list contents.
create function mylist_private.admin_overview() returns jsonb language plpgsql security definer set search_path='' as $$begin
 if not mylist_private.is_admin() then raise exception 'Acces rezervat administratorului MyList';end if;
 return jsonb_build_object('families',(select coalesce(jsonb_agg(to_jsonb(f) order by f.created_at),'[]') from public.mylist_families f),'accounts',(select coalesce(jsonb_agg(to_jsonb(a) order by a.invited_at),'[]') from public.mylist_accounts a),'invitations',(select coalesce(jsonb_agg(to_jsonb(i)-'delivery_key' order by i.created_at desc),'[]') from public.mylist_invitations i),'profiles',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from public.mylist_profiles p));end$$;
create function public.mylist_admin_overview() returns jsonb language sql security invoker set search_path='' as $$select mylist_private.admin_overview()$$;
create function mylist_private.admin_pending_count() returns integer language sql stable security definer set search_path='' as $$select case when mylist_private.is_admin() then (select count(*)::integer from public.mylist_invitations where status='pending') else 0 end$$;
create function public.mylist_admin_pending_count() returns integer language sql security invoker set search_path='' as $$select mylist_private.admin_pending_count()$$;
-- Only the verified server function can reserve/send an invitation. Locking prevents overbooking.
create function mylist_private.mylist_reserve_invite(actor uuid,recipient text,invite_kind text default 'family') returns jsonb language plpgsql security definer set search_path='' as $$
declare a record;old record;f uuid;i uuid;k uuid:=gen_random_uuid();em text:=lower(trim(recipient));begin
 select * into a from public.mylist_accounts where user_id=actor and accepted_at is not null;
 if not found then raise exception 'Accès indisponibil';end if;
 if em!~'^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' or length(em)>254 then raise exception 'Adresă de e-mail invalidă';end if;
 perform pg_advisory_xact_lock(hashtextextended(em,0));
 if invite_kind='administrator' then
  if not a.is_admin then raise exception 'Doar administratorul MyList';end if;
  select id into f from public.mylist_families where owner_email=em;
  if f is null then insert into public.mylist_families(owner_email) values(em) returning id into f;end if;
 elsif invite_kind='family' then
  f:=a.family_id;
  if not exists(select 1 from public.mylist_families where id=f and admin_id=actor) then raise exception 'Doar administratorul familiei poate invita membri';end if;
 else raise exception 'Tip de invitație invalid';end if;
 perform 1 from public.mylist_families where id=f for update;
 select * into old from public.mylist_accounts where email=em;
 if found then
  if old.accepted_at is not null or old.family_id<>f then raise exception 'Adresa are deja acces sau o invitație activă';end if;
  select * into old from public.mylist_invitations where email=em and status='pending';
  if old.created_at>now()-interval '1 minute' or old.sent_at>now()-interval '1 minute' or (old.delivery_key is not null and old.delivery_started_at>now()-interval '2 minutes') then raise exception 'Așteaptă un minut înainte să retrimiți invitația';end if;
  i:=old.id;
 else
  if (select count(*) from public.mylist_accounts where family_id=f)>=4 then raise exception 'Familia are deja 4 locuri ocupate, inclusiv invitațiile în așteptare';end if;
  insert into public.mylist_accounts(email,family_id,invited_by) values(em,f,actor);
  insert into public.mylist_invitations(family_id,email,invited_by,kind) values(f,em,actor,invite_kind) returning id into i;
 end if;
 update public.mylist_invitations set delivery_key=k,delivery_started_at=now() where id=i;
 return jsonb_build_object('id',i,'delivery_key',k);
end$$;
create function mylist_private.mylist_finish_invite(invitation_id uuid,delivery uuid,delivered boolean) returns void language plpgsql security definer set search_path='' as $$
declare i record;begin
 select * into i from public.mylist_invitations where id=invitation_id;
 if not found then return;end if;
 perform 1 from public.mylist_families where id=i.family_id for update;
 select * into i from public.mylist_invitations where id=invitation_id and delivery_key=delivery for update;
 if not found then return;end if;
 if delivered then update public.mylist_invitations set sent_at=now(),send_count=send_count+1,delivery_key=null where id=i.id;
 else
  update public.mylist_invitations set delivery_key=null where id=i.id;
  if i.send_count=0 and i.status='pending' then
   update public.mylist_invitations set status='failed' where id=i.id;
   delete from public.mylist_accounts where email=i.email and accepted_at is null;
  end if;
 end if;
end$$;
revoke all on function mylist_private.family_id(),mylist_private.family_admin(),mylist_private.action(text,jsonb),mylist_private.admin_overview(),mylist_private.admin_pending_count(),public.mylist_admin_overview(),public.mylist_admin_pending_count() from public,anon;
grant execute on function mylist_private.family_id(),mylist_private.family_admin(),mylist_private.action(text,jsonb),mylist_private.admin_overview(),mylist_private.admin_pending_count(),public.mylist_admin_overview(),public.mylist_admin_pending_count() to authenticated;

create function public.mylist_reserve_invite(actor uuid,recipient text,invite_kind text default 'family') returns jsonb language sql security invoker set search_path='' as $$select mylist_private.mylist_reserve_invite(actor,recipient,invite_kind)$$;

create function public.mylist_finish_invite(invitation_id uuid,delivery uuid,delivered boolean) returns void language sql security invoker set search_path='' as $$select mylist_private.mylist_finish_invite(invitation_id,delivery,delivered)$$;

grant usage on schema mylist_private to service_role;
revoke all on function public.mylist_reserve_invite(uuid,text,text),public.mylist_finish_invite(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.mylist_reserve_invite(uuid,text,text),public.mylist_finish_invite(uuid,uuid,boolean) to service_role;
revoke all on function mylist_private.mylist_reserve_invite(uuid,text,text),mylist_private.mylist_finish_invite(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function mylist_private.mylist_reserve_invite(uuid,text,text),mylist_private.mylist_finish_invite(uuid,uuid,boolean) to service_role;
