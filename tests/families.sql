begin;
-- Transactional fixtures: no mail is sent and nothing survives ROLLBACK.
create temp table qa_ids as select gen_random_uuid() a,gen_random_uuid() b,gen_random_uuid() c,gen_random_uuid() d,gen_random_uuid() e,gen_random_uuid() fa,gen_random_uuid() fb;
grant select on qa_ids to authenticated;
insert into auth.users(id,email,aud,role,email_confirmed_at) select a,'qa-a@example.invalid','authenticated','authenticated',now() from qa_ids union all select b,'qa-b@example.invalid','authenticated','authenticated',now() from qa_ids union all select c,'qa-c@example.invalid','authenticated','authenticated',now() from qa_ids union all select d,'qa-d@example.invalid','authenticated','authenticated',now() from qa_ids union all select e,'qa-e@example.invalid','authenticated','authenticated',now() from qa_ids;
insert into public.mylist_families(id,owner_email,admin_id) select fa,'qa-a@example.invalid',a from qa_ids union all select fb,'qa-c@example.invalid',c from qa_ids;
insert into public.mylist_accounts(email,user_id,family_id,accepted_at) select 'qa-a@example.invalid',a,fa,now() from qa_ids union all select 'qa-b@example.invalid',b,fa,now() from qa_ids union all select 'qa-c@example.invalid',c,fb,now() from qa_ids union all select 'qa-d@example.invalid',d,fb,now() from qa_ids;
insert into public.mylist_profiles(user_id,alias,color) select a,'QA A','blue' from qa_ids union all select c,'QA C','red' from qa_ids;
-- Server reservations and hard quota, without invoking email delivery.
do $$declare x record;r jsonb;denied boolean;begin
 select * into x from qa_ids;
 r:=public.mylist_reserve_invite(x.a,'qa-seat3@example.invalid','family');
 perform public.mylist_finish_invite((r->>'id')::uuid,(r->>'delivery_key')::uuid,true);
 perform public.mylist_reserve_invite(x.a,'qa-seat4@example.invalid','family');
 denied:=false;begin perform public.mylist_reserve_invite(x.a,'qa-seat5@example.invalid','family');exception when others then if sqlerrm not like 'Familia are deja 4%' then raise;end if;denied:=true;end;
 if not denied then raise exception 'Fifth seat allowed';end if;
 denied:=false;begin perform public.mylist_reserve_invite(x.b,'qa-unauthorized@example.invalid','family');exception when others then denied:=true;end;
 if not denied then raise exception 'Member can invite';end if;
 denied:=false;begin perform public.mylist_reserve_invite(x.a,'qa-root@example.invalid','administrator');exception when others then denied:=true;end;
 if not denied then raise exception 'Family admin can create root families';end if;
end$$;
select set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','email','qa-a@example.invalid')::text,true) from qa_ids;
set local role authenticated;
do $$declare x record;lid uuid;denied boolean;begin
 select * into x from qa_ids;
 if (select count(*) from public.mylist_accounts)<>4 then raise exception 'Account RLS leaks other family';end if;
 if (select count(*) from public.mylist_families)<>1 then raise exception 'Family RLS leaks';end if;
 if exists(select 1 from public.mylist_profiles where user_id=x.c) then raise exception 'Profile RLS leaks';end if;
 denied:=false;begin perform public.mylist_admin_overview();exception when others then denied:=true;end;if not denied then raise exception 'Family admin can see global dashboard';end if;
 denied:=false;begin perform public.mylist_reserve_invite(x.a,'qa-bypass@example.invalid','family');exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Browser can call server reservation';end if;
 denied:=false;begin perform mylist_private.list_action_v1('create','{"name":"Bypass"}');exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Legacy action bypass';end if;
 lid:=(public.mylist_action('create','{"name":"QA personal list"}')->>'id')::uuid;
 perform public.mylist_action('share',jsonb_build_object('list_id',lid,'user_id',x.b));
 denied:=false;begin perform public.mylist_action('share',jsonb_build_object('list_id',lid,'user_id',x.c));exception when others then denied:=true;end;if not denied then raise exception 'Cross family share allowed';end if;
 denied:=false;begin perform public.mylist_action('remove_account','{"email":"qa-b@example.invalid"}');exception when others then denied:=true;end;if not denied then raise exception 'Family admin can remove global accounts';end if;
 perform public.mylist_action('cancel_invite','{"email":"qa-seat4@example.invalid"}');
 denied:=false;begin perform public.mylist_action('cancel_invite','{"email":"qa-c@example.invalid"}');exception when others then denied:=true;end;if not denied then raise exception 'Cross-family cancellation allowed';end if;
end$$;
reset role;
do $$declare x record;r jsonb;rootid uuid;begin
 select * into x from qa_ids;
 r:=public.mylist_reserve_invite(x.a,'qa-delivery-fail@example.invalid','family');
 perform public.mylist_finish_invite((r->>'id')::uuid,(r->>'delivery_key')::uuid,false);
 if exists(select 1 from public.mylist_accounts where email='qa-delivery-fail@example.invalid') then raise exception 'Failed delivery keeps seat';end if;
 if not exists(select 1 from public.mylist_invitations where id=(r->>'id')::uuid and status='failed') then raise exception 'Failed delivery audit missing';end if;
 select user_id into rootid from public.mylist_accounts where is_admin limit 1;
 r:=public.mylist_reserve_invite(rootid,'qa-e@example.invalid','administrator');
 perform public.mylist_finish_invite((r->>'id')::uuid,(r->>'delivery_key')::uuid,true);
end$$;
select set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated','email','qa-e@example.invalid')::text,true) from qa_ids;
set local role authenticated;
select public.mylist_action('accept','{}');
do $$begin
 if not mylist_private.family_admin() then raise exception 'Invited admin not promoted to family admin';end if;
 if (select count(*) from public.mylist_accounts)<>1 then raise exception 'New family sees existing accounts';end if;
 if (select count(*) from public.mylist_lists)<>0 then raise exception 'Private list leak';end if;
 if (select count(*) from public.mylist_invitations where status='accepted')<>1 then raise exception 'Accepted invitation status missing';end if;
end$$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',user_id,'role','authenticated','email',email)::text,true) from public.mylist_accounts where is_admin limit 1;
set local role authenticated;
do $$begin
 if jsonb_array_length(public.mylist_admin_overview()->'families')<4 then raise exception 'Global dashboard incomplete';end if;
 perform public.mylist_action('remove_account','{"email":"qa-b@example.invalid"}');
end$$;
reset role;
do $$begin
 if exists(select 1 from public.mylist_accounts where email='qa-b@example.invalid') then raise exception 'Removal incomplete';end if;
 if not exists(select 1 from auth.users where email='qa-b@example.invalid') then raise exception 'Shared Auth identity deleted';end if;
end$$;
rollback;
select 'Passed: 4-seat quota, reservation rollback, family/account/profile/list isolation, protected RPCs, scoped sharing/cancellation, administrator acceptance, global overview and scoped account removal. Fixtures rolled back; no emails sent.' as verification;
