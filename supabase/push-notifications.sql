-- MyList v2.3.0: additive, dormant until push config is enabled at release.
create table public.mylist_push_config (
 id boolean primary key default true check(id), keys jsonb not null,
 enabled boolean not null default false
);
create table public.mylist_push_subscriptions (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 session_id uuid not null, endpoint text not null unique check(length(endpoint)<2048),
 subscription jsonb not null, app_url text not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index mylist_push_subscriptions_user_idx on public.mylist_push_subscriptions(user_id);
create table public.mylist_push_preferences (
 user_id uuid primary key references auth.users(id) on delete cascade,
 item_added boolean not null default true, list_shared boolean not null default true,
 list_completed boolean not null default true, item_toggled boolean not null default false
);
create table public.mylist_push_list_preferences (
 user_id uuid not null references auth.users(id) on delete cascade,
 list_id uuid not null references public.mylist_lists(id) on delete cascade,
 enabled boolean not null default true, primary key(user_id,list_id)
);
create index mylist_push_list_preferences_list_idx on public.mylist_push_list_preferences(list_id);
create table public.mylist_push_queue (
 id bigint generated always as identity primary key,
 subscription_id uuid not null references public.mylist_push_subscriptions(id) on delete cascade,
 list_id uuid not null references public.mylist_lists(id) on delete cascade,
 kind text not null check(kind in ('item_added','item_toggled','list_shared','list_completed')),
 bucket bigint not null, event_count int not null default 1, last_name text not null default '',
 due_at timestamptz not null, created_at timestamptz not null default now(),
 claim_token uuid, locked_until timestamptz, attempts int not null default 0,
 finished_at timestamptz, outcome text,
 unique(subscription_id,list_id,kind,bucket)
);
create index mylist_push_queue_due_idx on public.mylist_push_queue(due_at) where finished_at is null;
alter table public.mylist_push_config enable row level security;
alter table public.mylist_push_subscriptions enable row level security;
alter table public.mylist_push_preferences enable row level security;
alter table public.mylist_push_list_preferences enable row level security;
alter table public.mylist_push_queue enable row level security;
revoke all on public.mylist_push_config,public.mylist_push_subscriptions,public.mylist_push_preferences,public.mylist_push_list_preferences,public.mylist_push_queue from public,anon,authenticated;
grant all on public.mylist_push_config,public.mylist_push_subscriptions,public.mylist_push_preferences,public.mylist_push_list_preferences,public.mylist_push_queue to service_role;
grant usage,select on sequence public.mylist_push_queue_id_seq to service_role;
-- Browser preferences use normal RLS; subscription credentials remain server-only.
grant select,insert,update on public.mylist_push_preferences,public.mylist_push_list_preferences to authenticated;
create policy push_pref_read on public.mylist_push_preferences for select to authenticated using(user_id=(select auth.uid()) and mylist_private.allowed());
create policy push_pref_insert on public.mylist_push_preferences for insert to authenticated with check(user_id=(select auth.uid()) and mylist_private.allowed());
create policy push_pref_update on public.mylist_push_preferences for update to authenticated using(user_id=(select auth.uid()) and mylist_private.allowed()) with check(user_id=(select auth.uid()) and mylist_private.allowed());
create policy push_list_read on public.mylist_push_list_preferences for select to authenticated using(user_id=(select auth.uid()) and mylist_private.access_list(list_id));
create policy push_list_insert on public.mylist_push_list_preferences for insert to authenticated with check(user_id=(select auth.uid()) and mylist_private.access_list(list_id) and exists(select 1 from public.mylist_members m where m.list_id=mylist_push_list_preferences.list_id));
create policy push_list_update on public.mylist_push_list_preferences for update to authenticated using(user_id=(select auth.uid()) and mylist_private.access_list(list_id)) with check(user_id=(select auth.uid()) and mylist_private.access_list(list_id) and exists(select 1 from public.mylist_members m where m.list_id=mylist_push_list_preferences.list_id));

-- Internal privileged predicates are not exposed to clients. No JWT metadata authorization.
create function mylist_private.push_allowed(uid uuid,lid uuid,kind text,sid uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.mylist_accounts a where a.user_id=uid and a.accepted_at is not null)
 and exists(select 1 from auth.sessions s where s.id=sid and s.user_id=uid and (s.not_after is null or s.not_after>now()))
 and exists(select 1 from public.mylist_lists l where l.id=lid and l.deleted_at is null
   and (l.owner_id=uid or exists(select 1 from public.mylist_members m where m.list_id=lid and m.user_id=uid))
   and exists(select 1 from public.mylist_members m where m.list_id=lid))
 and coalesce((select p.enabled from public.mylist_push_list_preferences p where p.user_id=uid and p.list_id=lid),true)
 and coalesce((select (to_jsonb(p)->>kind)::boolean from public.mylist_push_preferences p where p.user_id=uid),kind<>'item_toggled')
$$;
revoke all on function mylist_private.push_allowed(uuid,uuid,text,uuid) from public,anon,authenticated;

create function mylist_private.push_event() returns trigger language plpgsql security definer set search_path='' as $$
declare lid uuid; v_kind text; item_name text:=''; recipient uuid; win bigint:=floor(extract(epoch from clock_timestamp())/10); actor uuid:=auth.uid();
begin
 -- A dormant migration never enqueues or calls an external service.
 if not coalesce((select enabled from public.mylist_push_config where id),false) then return new;end if;
 if actor is null then return new;end if;
 if tg_table_name='mylist_items' then
  lid:=new.list_id; item_name:=new.name;
  if tg_op='INSERT' then v_kind:='item_added';elsif new.done is distinct from old.done then v_kind:='item_toggled';else return new;end if;
 elsif tg_table_name='mylist_lists' then
  lid:=new.id;if old.completed_at is null and new.completed_at is not null then v_kind:='list_completed';else return new;end if;
 else lid:=new.list_id;v_kind:='list_shared';recipient:=new.user_id;
 end if;
 insert into public.mylist_push_queue(subscription_id,list_id,kind,bucket,last_name,due_at)
 select s.id,lid,v_kind,win,left(item_name,160),to_timestamp((win+1)*10+2)
 from public.mylist_push_subscriptions s
 where s.user_id<>actor and (recipient is null or s.user_id=recipient)
 and mylist_private.push_allowed(s.user_id,lid,v_kind,s.session_id)
 on conflict(subscription_id,list_id,kind,bucket) do update
 set event_count=mylist_push_queue.event_count+1,last_name=excluded.last_name;
 return new;
end$$;
revoke all on function mylist_private.push_event() from public,anon,authenticated;
create trigger mylist_push_item after insert or update of done on public.mylist_items for each row execute function mylist_private.push_event();
create trigger mylist_push_complete after update of completed_at on public.mylist_lists for each row execute function mylist_private.push_event();
create trigger mylist_push_share after insert on public.mylist_members for each row execute function mylist_private.push_event();

create function mylist_private.push_cleanup_access() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='mylist_members' then
  delete from public.mylist_push_list_preferences where user_id=old.user_id and list_id=old.list_id;
  delete from public.mylist_push_queue q using public.mylist_push_subscriptions s where q.subscription_id=s.id and s.user_id=old.user_id and q.list_id=old.list_id;
 else
  delete from public.mylist_push_subscriptions where user_id=old.user_id;
  delete from public.mylist_push_preferences where user_id=old.user_id;
  delete from public.mylist_push_list_preferences where user_id=old.user_id;
 end if;return old;
end$$;
revoke all on function mylist_private.push_cleanup_access() from public,anon,authenticated;
create trigger mylist_push_revoke after delete on public.mylist_members for each row execute function mylist_private.push_cleanup_access();
create trigger mylist_push_remove_account after delete on public.mylist_accounts for each row execute function mylist_private.push_cleanup_access();

create function public.mylist_push_session(uid uuid,sid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.mylist_accounts where user_id=uid and accepted_at is not null)
 and exists(select 1 from auth.sessions where id=sid and user_id=uid and (not_after is null or not_after>now()))
$$;
-- Atomic lease prevents overlapping workers from sending the same job concurrently.
create function public.mylist_push_claim() returns setof public.mylist_push_queue language sql security definer set search_path='' as $$
 update public.mylist_push_queue q set claim_token=gen_random_uuid(),locked_until=now()+interval '90 seconds',attempts=q.attempts+1
 where q.id in(select id from public.mylist_push_queue where finished_at is null and due_at<=now() and (locked_until is null or locked_until<now()) and attempts<5 order by due_at limit 50 for update skip locked)
 and coalesce((select enabled from public.mylist_push_config where id),false)
 returning q.*
$$;
create function public.mylist_push_target(job bigint,token uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('subscription_id',s.id,'user_id',s.user_id,'subscription',s.subscription,'app_url',s.app_url,'list_name',left(l.name,100))
 from public.mylist_push_queue q join public.mylist_push_subscriptions s on s.id=q.subscription_id join public.mylist_lists l on l.id=q.list_id
 where q.id=job and q.claim_token=token and q.finished_at is null and q.locked_until>now()
 and mylist_private.push_allowed(s.user_id,q.list_id,q.kind,s.session_id)
$$;
revoke all on function public.mylist_push_session(uuid,uuid),public.mylist_push_claim(),public.mylist_push_target(bigint,uuid) from public,anon,authenticated;
grant execute on function public.mylist_push_session(uuid,uuid),public.mylist_push_claim(),public.mylist_push_target(bigint,uuid) to service_role;

create function mylist_private.push_tick() returns void language plpgsql security definer set search_path='' as $$
begin
 delete from public.mylist_push_queue where created_at<now()-interval '7 days' or (attempts>=5 and locked_until<now());
 delete from public.mylist_push_subscriptions s where not exists(select 1 from auth.sessions a where a.id=s.session_id and a.user_id=s.user_id and (a.not_after is null or a.not_after>now())) or not exists(select 1 from public.mylist_accounts a where a.user_id=s.user_id and a.accepted_at is not null);
 if coalesce((select enabled from public.mylist_push_config where id),false) and exists(select 1 from public.mylist_push_queue where finished_at is null and due_at<=now() and (locked_until is null or locked_until<now())) then
  perform net.http_post(url:='https://radskybbymadavveatzn.supabase.co/functions/v1/mylist-push',headers:=jsonb_build_object('Content-Type','application/json','x-mylist-dispatch',(select keys->>'dispatchToken' from public.mylist_push_config where id)),body:='{"action":"dispatch"}'::jsonb,timeout_milliseconds:=30000);
 end if;
end$$;
revoke all on function mylist_private.push_tick() from public,anon,authenticated;
-- Release activation (separate from migration): cron.schedule('mylist-push','10 seconds','select mylist_private.push_tick()');
