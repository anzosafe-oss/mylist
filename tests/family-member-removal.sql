begin;
-- No email delivery. Isolated users, lists and households are rolled back.
create temp table removal_qa as select gen_random_uuid() a,gen_random_uuid() b,gen_random_uuid() c,gen_random_uuid() d,gen_random_uuid() e,gen_random_uuid() f,gen_random_uuid() fa,gen_random_uuid() fb,gen_random_uuid() la,gen_random_uuid() lb;
grant select on removal_qa to authenticated;
insert into auth.users(id,email,aud,role,email_confirmed_at)
 select a,'qa-family-a@example.invalid','authenticated','authenticated',now() from removal_qa union all
 select b,'qa-family-b@example.invalid','authenticated','authenticated',now() from removal_qa union all
 select c,'qa-family-c@example.invalid','authenticated','authenticated',now() from removal_qa union all
 select d,'qa-family-d@example.invalid','authenticated','authenticated',now() from removal_qa union all
 select e,'qa-family-e@example.invalid','authenticated','authenticated',now() from removal_qa union all
 select f,'qa-family-f@example.invalid','authenticated','authenticated',now() from removal_qa;
insert into public.mylist_families(id,owner_email,admin_id)
 select fa,'qa-family-a@example.invalid',a from removal_qa union all select fb,'qa-family-e@example.invalid',e from removal_qa;
insert into public.mylist_accounts(email,user_id,family_id,accepted_at)
 select 'qa-family-a@example.invalid',a,fa,now() from removal_qa union all
 select 'qa-family-b@example.invalid',b,fa,now() from removal_qa union all
 select 'qa-family-c@example.invalid',c,fa,now() from removal_qa union all
 select 'qa-family-d@example.invalid',d,fa,now() from removal_qa union all
 select 'qa-family-e@example.invalid',e,fb,now() from removal_qa union all
 select 'qa-family-f@example.invalid',f,fb,now() from removal_qa;
insert into public.mylist_invitations(family_id,email,invited_by,kind,status,send_count,accepted_at)
 select fa,'qa-family-b@example.invalid',a,'family','accepted',1,now() from removal_qa;
insert into public.mylist_profiles(user_id,alias,color) select b,'QA member','blue' from removal_qa;
insert into public.mylist_lists(id,owner_id,name) select la,a,'QA shared list' from removal_qa union all select lb,b,'QA retained owned list' from removal_qa;
insert into public.mylist_members(list_id,user_id) select la,b from removal_qa union all select la,c from removal_qa union all select lb,a from removal_qa;
insert into public.mylist_items(list_id,name) select lb,'QA retained product' from removal_qa;
-- A regular member cannot manage family membership.
select set_config('request.jwt.claims',jsonb_build_object('sub',c,'role','authenticated','email','qa-family-c@example.invalid')::text,true) from removal_qa;
set local role authenticated;
do $$declare denied boolean:=false;x record;begin
 select * into x from removal_qa;
 begin perform public.mylist_remove_family_member(x.b);exception when others then denied:=true;end;
 if not denied then raise exception 'Regular member removed someone';end if;
end$$;
reset role;
-- Household admin A has no global-admin privilege.
select set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','email','qa-family-a@example.invalid')::text,true) from removal_qa;
set local role authenticated;
do $$declare denied boolean;x record;r jsonb;begin
 select * into x from removal_qa;
 if (select count(*) from public.mylist_accounts)<>4 then raise exception 'Fixture is not a full household';end if;
 denied:=false;begin perform public.mylist_remove_family_member(x.a);exception when others then denied:=true;end;
 if not denied then raise exception 'Self-removal allowed';end if;
 denied:=false;begin perform public.mylist_remove_family_member(x.f);exception when others then denied:=true;end;
 if not denied then raise exception 'Cross-family removal allowed';end if;
 denied:=false;begin perform public.mylist_action('remove_account','{"email":"qa-family-b@example.invalid"}');exception when others then denied:=true;end;
 if not denied then raise exception 'Global administration privileges changed';end if;
 r:=public.mylist_remove_family_member(x.b);
 if r->>'available'<>'1' then raise exception 'Freed seat not returned';end if;
 if (select count(*) from public.mylist_accounts)<>3 then raise exception 'Seat not released';end if;
end$$;
reset role;
do $$declare x record;r jsonb;begin
 select * into x from removal_qa;
 if not exists(select 1 from auth.users where id=x.b) then raise exception 'Shared Auth identity was deleted';end if;
 if exists(select 1 from public.mylist_members where user_id=x.b) or exists(select 1 from public.mylist_profiles where user_id=x.b) then raise exception 'MyList access cleanup incomplete';end if;
 if not exists(select 1 from public.mylist_members where list_id=x.la and user_id=x.c) then raise exception 'Another participant was removed';end if;
 if not exists(select 1 from public.mylist_lists where id=x.lb) or not exists(select 1 from public.mylist_items where list_id=x.lb) or not exists(select 1 from public.mylist_members where list_id=x.lb and user_id=x.a) then raise exception 'Owned/shared lists were lost';end if;
 if not exists(select 1 from public.mylist_invitations where email='qa-family-b@example.invalid' and status='cancelled') then raise exception 'Invitation history not updated';end if;
 if has_function_privilege('anon','public.mylist_remove_family_member(uuid)','execute') then raise exception 'Anonymous RPC executable';end if;
 r:=public.mylist_reserve_invite(x.a,'qa-family-replacement@example.invalid','family');
 if (select count(*) from public.mylist_accounts where family_id=x.fa)<>4 then raise exception 'Replacement invite did not occupy free seat';end if;
 perform public.mylist_finish_invite((r->>'id')::uuid,(r->>'delivery_key')::uuid,false);
end$$;
-- Existing tokens of the removed member no longer grant MyList access.
select set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','email','qa-family-b@example.invalid')::text,true) from removal_qa;
set local role authenticated;
do $$declare x record;begin select * into x from removal_qa;if mylist_private.allowed() or mylist_private.access_list(x.lb) then raise exception 'Removed member retains access';end if;end$$;
reset role;
-- The protected global-admin flag is honored inside a household too.
update public.mylist_accounts set is_admin=true where user_id=(select c from removal_qa);
select set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','email','qa-family-a@example.invalid')::text,true) from removal_qa;
set local role authenticated;
do $$declare denied boolean:=false;x record;begin select * into x from removal_qa;begin perform public.mylist_remove_family_member(x.c);exception when others then denied:=true;end;if not denied then raise exception 'Protected administrator removed';end if;end$$;
reset role;
rollback;
select 'Passed: family-admin-only removal, self/global-admin protection, family isolation, immediate revocation, released/reusable seat, retained Auth identity and shared lists. All fixtures rolled back; no emails sent.' as verification;
