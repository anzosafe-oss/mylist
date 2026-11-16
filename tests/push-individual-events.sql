-- Live-safe fixture: only generated accounts/lists, no network calls; rolled back.
begin;
create temp table push_individual_fixture as select gen_random_uuid() a,gen_random_uuid() b,gen_random_uuid() sa,gen_random_uuid() sb,gen_random_uuid() family,gen_random_uuid() list,gen_random_uuid() muted_share;
insert into auth.users(id,email) select a,'push-individual-a-'||a||'@example.invalid' from push_individual_fixture union all select b,'push-individual-b-'||b||'@example.invalid' from push_individual_fixture;
insert into auth.sessions(id,user_id) select sa,a from push_individual_fixture union all select sb,b from push_individual_fixture;
insert into public.mylist_families(id,owner_email,admin_id) select family,'push-individual-a-'||a||'@example.invalid',a from push_individual_fixture;
insert into public.mylist_accounts(email,user_id,accepted_at,family_id) select 'push-individual-a-'||a||'@example.invalid',a,now(),family from push_individual_fixture union all select 'push-individual-b-'||b||'@example.invalid',b,now(),family from push_individual_fixture;
insert into public.mylist_lists(id,owner_id,name) select list,a,'Individual push fixture' from push_individual_fixture;
select set_config('request.jwt.claim.sub',a::text,true) from push_individual_fixture;
insert into public.mylist_members(list_id,user_id) select list,b from push_individual_fixture;
insert into public.mylist_push_subscriptions(user_id,session_id,endpoint,subscription,app_url) select a,sa,'https://web.push.apple.com/fixture-a-'||a,'{}'::jsonb,'https://anzosafe-oss.github.io/mylist/' from push_individual_fixture union all select b,sb,'https://web.push.apple.com/fixture-b-'||b,'{}'::jsonb,'https://anzosafe-oss.github.io/mylist/' from push_individual_fixture;
insert into public.mylist_items(list_id,name,quantity,unit,position) select list,'Lapte',1,'buc.',1024 from push_individual_fixture;
insert into public.mylist_items(list_id,name,quantity,unit,position) select list,'Ouă',1,'buc.',2048 from push_individual_fixture;
do $$begin
 assert (select count(*)=2 and count(distinct bucket)=2 and bool_and(event_count=1) from public.mylist_push_queue where list_id=(select list from push_individual_fixture)),'rapid changes must remain separate';
 assert not exists(select 1 from public.mylist_push_queue q join public.mylist_push_subscriptions s on s.id=q.subscription_id where q.list_id=(select list from push_individual_fixture) and s.user_id=(select a from push_individual_fixture)),'no own notification';
end$$;
insert into public.mylist_push_preferences(user_id,item_added,list_shared,list_completed,item_toggled) select b,false,false,false,true from push_individual_fixture;
insert into public.mylist_items(list_id,name,quantity,unit,position) select list,'Oprit',1,'buc.',3072 from push_individual_fixture;
update public.mylist_items set done=true where list_id=(select list from push_individual_fixture) and name='Lapte';
update public.mylist_lists set completed_at=now() where id=(select list from push_individual_fixture);
insert into public.mylist_lists(id,owner_id,name) select muted_share,a,'Muted share fixture' from push_individual_fixture;
insert into public.mylist_members(list_id,user_id) select muted_share,b from push_individual_fixture;
-- A separate list tests muted sharing without changing existing membership.
do $$begin assert not exists(select 1 from public.mylist_push_queue where list_id=(select muted_share from push_individual_fixture)),'share muted';end$$;
update public.mylist_lists set completed_at=null where id=(select list from push_individual_fixture);
update public.mylist_items set done=false where list_id=(select list from push_individual_fixture) and name='Lapte';
do $$begin
 assert (select count(*)=2 from public.mylist_push_queue where list_id=(select list from push_individual_fixture) and kind='item_toggled'),'toggle opt-in';
 assert (select count(*)=2 from public.mylist_push_queue where list_id=(select list from push_individual_fixture) and kind='item_added'),'add muted';
 assert not exists(select 1 from public.mylist_push_queue where list_id=(select list from push_individual_fixture) and kind='list_completed'),'completion muted';
end$$;
update public.mylist_push_preferences set item_added=true,list_completed=true,list_shared=true,item_toggled=false where user_id=(select b from push_individual_fixture);
insert into public.mylist_items(list_id,name,quantity,unit,position) select list,'Pornit',1,'buc.',4096 from push_individual_fixture;
update public.mylist_lists set completed_at=now() where id=(select list from push_individual_fixture);
do $$begin
 assert (select count(*)=6 from public.mylist_push_queue where list_id=(select list from push_individual_fixture)),'independent added and completed enabled';
 assert (select bool_and(event_count=1) from public.mylist_push_queue where list_id=(select list from push_individual_fixture)),'no batches';
end$$;
select 'PASS: individual delivery IDs, no batching, own-action exclusion, independent event preferences' as result;
rollback;
