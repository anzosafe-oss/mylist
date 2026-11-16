-- Fully rolled back fixtures. No network calls, user accounts or list changes persist.
begin;
create temp table push_fixture as select gen_random_uuid() a,gen_random_uuid() b,gen_random_uuid() stranger,gen_random_uuid() sa,gen_random_uuid() sb,gen_random_uuid() ss,gen_random_uuid() list,gen_random_uuid() personal,gen_random_uuid() item,gen_random_uuid() family;
grant select on push_fixture to authenticated;
insert into auth.users(id,email) select a,'push-a-'||a||'@example.invalid' from push_fixture union all select b,'push-b-'||b||'@example.invalid' from push_fixture union all select stranger,'push-c-'||stranger||'@example.invalid' from push_fixture;
insert into auth.sessions(id,user_id) select sa,a from push_fixture union all select sb,b from push_fixture union all select ss,stranger from push_fixture;
insert into public.mylist_families(id,owner_email,admin_id) select family,'push-a-'||a||'@example.invalid',a from push_fixture;
insert into public.mylist_accounts(email,user_id,accepted_at,family_id) select 'push-a-'||a||'@example.invalid',a,now(),family from push_fixture union all select 'push-b-'||b||'@example.invalid',b,now(),family from push_fixture union all select 'push-c-'||stranger||'@example.invalid',stranger,now(),family from push_fixture;
insert into public.mylist_push_config(id,keys,enabled) values(true,'{"dispatchToken":"fixture-only"}',true);
insert into public.mylist_lists(id,owner_id,name) select list,a,'Push fixture shared' from push_fixture union all select personal,a,'Push fixture personal' from push_fixture;
insert into public.mylist_push_subscriptions(user_id,session_id,endpoint,subscription,app_url) select a,sa,'https://fcm.googleapis.com/fixture-a-'||a,'{}'::jsonb,'https://anzosafe-oss.github.io/mylist/' from push_fixture union all select b,sb,'https://fcm.googleapis.com/fixture-b-'||b,'{}'::jsonb,'https://anzosafe-oss.github.io/mylist/' from push_fixture;
select set_config('request.jwt.claim.sub',a::text,true) from push_fixture;
insert into public.mylist_members(list_id,user_id) select list,b from push_fixture;
insert into public.mylist_items(id,list_id,name,quantity,unit,position) select item,list,'Lapte',1,'buc.',1024 from push_fixture;
insert into public.mylist_items(list_id,name,quantity,unit,position) select list,'Ouă',1,'buc.',2048 from push_fixture;
insert into public.mylist_items(list_id,name,quantity,unit,position) select personal,'Privat',1,'buc.',1024 from push_fixture;
do $$begin
 assert (select count(*)=2 and sum(event_count)=2 and bool_and(event_count=1) from public.mylist_push_queue where kind='item_added'),'separate additions';
 assert (select count(*)=1 from public.mylist_push_queue where kind='list_shared'),'share recipient';
 assert not exists(select 1 from public.mylist_push_queue q join public.mylist_push_subscriptions s on s.id=q.subscription_id join push_fixture f on s.user_id=f.a),'own actions suppressed';
 assert not exists(select 1 from public.mylist_push_queue q join push_fixture f on q.list_id=f.personal),'personal excluded';
end$$;
update public.mylist_items set done=true where id=(select item from push_fixture);
do $$begin assert not exists(select 1 from public.mylist_push_queue where kind='item_toggled'),'toggle off by default';end$$;
insert into public.mylist_push_preferences(user_id,item_toggled) select b,true from push_fixture;
update public.mylist_items set done=false where id=(select item from push_fixture);
do $$begin assert (select count(*)=1 from public.mylist_push_queue where kind='item_toggled'),'toggle opt-in';end$$;
insert into public.mylist_push_list_preferences(user_id,list_id,enabled) select b,list,false from push_fixture;
insert into public.mylist_items(list_id,name,quantity,unit,position) select list,'Mut',1,'buc.',3072 from push_fixture;
do $$begin assert (select sum(event_count)=2 from public.mylist_push_queue where kind='item_added'),'muted list';end$$;
update public.mylist_push_list_preferences set enabled=true;
update public.mylist_lists set completed_at=now() where id=(select list from push_fixture);
update public.mylist_lists set completed_at=now() where id=(select list from push_fixture);
do $$begin assert (select count(*)=1 from public.mylist_push_queue where kind='list_completed'),'complete once';end$$;
-- Claim isolation and send-time preference recheck.
update public.mylist_push_queue set due_at=now()-interval '1 second';
create temp table claimed as select * from public.mylist_push_claim();
do $$begin
 assert (select count(*)>0 from claimed),'jobs claimed';
 assert not exists(select 1 from public.mylist_push_claim()),'no concurrent double claim';
 assert (select public.mylist_push_target(id,claim_token) is not null from claimed limit 1),'valid target';
end$$;
update public.mylist_push_list_preferences set enabled=false;
do $$begin assert (select public.mylist_push_target(id,claim_token) is null from claimed limit 1),'mute at send time';end$$;
update public.mylist_push_list_preferences set enabled=true;
-- Existing roles cannot read credentials or another user's preferences.
select set_config('request.jwt.claim.sub',b::text,true) from push_fixture;
set local role authenticated;
do $$begin
 assert (select count(*)=1 from public.mylist_push_preferences),'own preferences readable';
 begin perform * from public.mylist_push_config;raise exception 'secret exposed';exception when insufficient_privilege then null;end;
 begin perform * from public.mylist_push_subscriptions;raise exception 'subscriptions exposed';exception when insufficient_privilege then null;end;
 begin perform public.mylist_push_claim();raise exception 'worker RPC exposed';exception when insufficient_privilege then null;end;
 begin insert into public.mylist_push_preferences(user_id) select a from push_fixture;raise exception 'cross-user write';exception when insufficient_privilege then null;end;
end$$;
reset role;
select set_config('request.jwt.claim.sub',stranger::text,true) from push_fixture;
set local role authenticated;
do $$begin
 assert not exists(select 1 from public.mylist_push_preferences),'other preferences hidden';
 begin insert into public.mylist_push_list_preferences(user_id,list_id) select stranger,list from push_fixture;raise exception 'inaccessible list write';exception when insufficient_privilege then null;end;
end$$;
reset role;
delete from auth.sessions where id=(select sb from push_fixture);
do $$begin assert (select public.mylist_push_target(id,claim_token) is null from claimed limit 1),'logged out session excluded';end$$;
insert into auth.sessions(id,user_id) select sb,b from push_fixture;
delete from public.mylist_members where list_id=(select list from push_fixture);
do $$begin
 assert not exists(select 1 from public.mylist_push_queue),'revocation removes queued jobs';
 assert not exists(select 1 from public.mylist_push_list_preferences),'revocation resets preferences';
end$$;
delete from public.mylist_accounts where user_id=(select b from push_fixture);
do $$begin assert not exists(select 1 from public.mylist_push_subscriptions where user_id=(select b from push_fixture)),'account removal cleans subscriptions';end$$;
select 'PASS: individual events, defaults, own/personal exclusions, RLS, leases, preferences, logout, revocation and account cleanup' as result;
rollback;
