begin;
do $test$
declare
 admin_id uuid;
 target_id uuid:=gen_random_uuid();
 admin_list uuid:=gen_random_uuid();
 target_list uuid:=gen_random_uuid();
 test_email text:='mylist-account-test-'||target_id::text||'@example.invalid';
 pending_email text:='mylist-pending-test-'||target_id::text||'@example.invalid';
 admin_email text;
 denied boolean;
begin
 select user_id,email into admin_id,admin_email from public.mylist_accounts where is_admin and accepted_at is not null limit 1;
 if admin_id is null then raise exception 'Missing administrator fixture';end if;
 insert into auth.users(id,email,aud,role,email_confirmed_at) values(target_id,test_email,'authenticated','authenticated',now());
 insert into public.mylist_accounts(email,user_id,is_admin,accepted_at) values(test_email,target_id,false,now());
 insert into public.mylist_accounts(email) values(pending_email);
 insert into public.mylist_profiles(user_id,alias,color) values(target_id,'Test cont','blue');
 insert into public.mylist_lists(id,owner_id,name) values(admin_list,admin_id,'QA account administration'),(target_list,target_id,'QA preserved list');
 insert into public.mylist_members(list_id,user_id) values(admin_list,target_id),(target_list,admin_id);
 insert into public.mylist_items(list_id,name) values(target_list,'QA preserved item');
 perform set_config('request.jwt.claims','{}',true);
 denied:=false;
 begin perform public.mylist_action('remove_account',jsonb_build_object('email',test_email));exception when others then if sqlerrm<>'Autentificare necesară' then raise;end if;denied:=true;end;
 if not denied then raise exception 'Anonymous removal was allowed';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',target_id,'role','authenticated','email',test_email)::text,true);
 denied:=false;
 begin perform public.mylist_action('remove_account',jsonb_build_object('email',pending_email));exception when others then if sqlerrm<>'Doar administratorul poate șterge conturi din MyList' then raise;end if;denied:=true;end;
 if not denied then raise exception 'Member removal was allowed';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated','email',admin_email)::text,true);
 denied:=false;
 begin perform public.mylist_action('remove_account',jsonb_build_object('email',admin_email));exception when others then if sqlerrm<>'Contul de administrator nu poate fi șters' then raise;end if;denied:=true;end;
 if not denied then raise exception 'Administrator removal was allowed';end if;
 perform public.mylist_action('remove_account',jsonb_build_object('email',upper(test_email)));
 if exists(select 1 from public.mylist_accounts where email=test_email) or exists(select 1 from public.mylist_members where user_id=target_id) or exists(select 1 from public.mylist_profiles where user_id=target_id) then raise exception 'Account cleanup incomplete';end if;
 if not exists(select 1 from auth.users where id=target_id) then raise exception 'Shared authentication user deleted';end if;
 if not exists(select 1 from public.mylist_lists where id=target_list) or not exists(select 1 from public.mylist_items where list_id=target_list) or not exists(select 1 from public.mylist_members where list_id=target_list and user_id=admin_id) then raise exception 'Owned or shared data was deleted';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',target_id,'role','authenticated','email',test_email)::text,true);
 if mylist_private.allowed() or mylist_private.access_list(target_list) or mylist_private.access_list(admin_list) then raise exception 'Removed user still has access';end if;
 denied:=false;
 begin perform public.mylist_action('create',jsonb_build_object('name','Forbidden'));exception when others then if sqlerrm<>'Ai nevoie de o invitație pentru MyList' then raise;end if;denied:=true;end;
 if not denied then raise exception 'Removed user can mutate';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated','email',admin_email)::text,true);
 perform public.mylist_action('remove_account',jsonb_build_object('email',pending_email));
 if exists(select 1 from public.mylist_accounts where email=pending_email) then raise exception 'Pending account cleanup incomplete';end if;
end
$test$;
rollback;
select 'Passed: administrator protection, anonymous/member denial, account and membership cleanup, retained shared data and Auth user, immediate access revocation; all fixtures rolled back.' as verification;