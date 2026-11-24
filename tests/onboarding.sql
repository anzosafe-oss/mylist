begin;
do $$declare u uuid:=gen_random_uuid();f uuid:=gen_random_uuid();begin
 insert into auth.users(id,email,email_confirmed_at) values(u,'alias-test@example.invalid',now());
 insert into public.mylist_families(id,owner_email) values(f,'alias-test@example.invalid');
 insert into public.mylist_accounts(email,user_id,family_id) values('alias-test@example.invalid',u,f);
 perform set_config('request.jwt.claim.sub',u::text,true);
 perform set_config('request.jwt.claims',json_build_object('sub',u,'email','alias-test@example.invalid','role','authenticated')::text,true);
end$$;
set local role authenticated;
select public.mylist_action('accept','{}');
insert into public.mylist_profiles(user_id,alias,color) values(auth.uid(),'Alias inițial','blue');
update public.mylist_profiles set alias='Alias modificat' where user_id=auth.uid();
do $$begin
 if not exists(select 1 from public.mylist_profiles where user_id=auth.uid() and alias='Alias modificat') then raise exception 'Alias update failed';end if;
 begin
  insert into public.mylist_profiles(user_id,alias,color) values(gen_random_uuid(),'Other','blue');
  raise exception 'Foreign profile insert allowed';
 exception when insufficient_privilege then null;end;
end$$;
reset role;rollback;
select 'PASS MyList: invitation acceptance, first alias, alias update and isolation; rolled back' as result;