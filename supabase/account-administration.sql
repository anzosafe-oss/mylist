-- Upgrade existing MyList installations. This defines the operation; it does not remove any account.
create or replace function mylist_private.action(op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
 if op='remove_account' then
  if not mylist_private.is_admin() then raise exception 'Doar administratorul poate șterge conturi din MyList';end if;
  select * into rec from public.mylist_accounts where email=lower(trim(p->>'email')) for update;
  if not found then raise exception 'Contul nu mai este disponibil';end if;
  if rec.is_admin or rec.user_id=uid then raise exception 'Contul de administrator nu poate fi șters';end if;
  target:=rec.user_id;
  if target is not null then
   delete from public.mylist_members where user_id=target;
   delete from public.mylist_profiles where user_id=target;
  end if;
  delete from public.mylist_accounts where email=rec.email;
  return jsonb_build_object('removed',true);
 end if;
 lid:=(p->>'list_id')::uuid;
 select owner_id into own from public.mylist_lists where id=lid and deleted_at is null for update;
 if own is null or not mylist_private.access_list(lid) then raise exception 'Lista nu este disponibilă';end if;
 if op in('rename','delete','share','revoke') and own<>uid then raise exception 'Doar proprietarul listei';end if;
 if op='rename' then update public.mylist_lists set name=trim(p->>'name') where id=lid;
 elsif op='delete' then update public.mylist_lists set deleted_at=now() where id=lid;
 elsif op='share' then
  target:=(p->>'user_id')::uuid;
  if target=own then raise exception 'Cont indisponibil';end if;
  perform 1 from public.mylist_accounts where user_id=target and accepted_at is not null for key share;
  if not found then raise exception 'Cont indisponibil';end if;
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