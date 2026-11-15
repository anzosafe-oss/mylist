-- Family administrators can remove only regular members of their own family.
-- Global account administration remains on its existing, separate RPC.
create or replace function mylist_private.remove_family_member(target_user_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();fid uuid;member_record record;begin
 if uid is null then raise exception 'Autentificare necesară';end if;
 select f.id into fid from public.mylist_families f
 join public.mylist_accounts a on a.family_id=f.id
 where f.admin_id=uid and a.user_id=uid and a.accepted_at is not null
 for update of f;
 if fid is null then raise exception 'Doar administratorul familiei poate șterge membri';end if;
 select * into member_record from public.mylist_accounts
 where user_id=target_user_id and family_id=fid and accepted_at is not null for update;
 if not found then raise exception 'Membrul nu mai este disponibil în familia ta';end if;
 if member_record.user_id=uid or member_record.is_admin or exists(
  select 1 from public.mylist_families where admin_id=member_record.user_id
 ) then raise exception 'Contul de administrator este protejat';end if;
 delete from public.mylist_members where user_id=member_record.user_id;
 delete from public.mylist_profiles where user_id=member_record.user_id;
 update public.mylist_invitations set status='cancelled',delivery_key=null
 where family_id=fid and email=member_record.email and status in('pending','accepted');
 delete from public.mylist_accounts where email=member_record.email and family_id=fid;
 -- Keep Auth identities, owned lists and other participants' access unchanged.
 return jsonb_build_object('removed',true,'available',4-(select count(*) from public.mylist_accounts where family_id=fid));
end$$;
revoke all on function mylist_private.remove_family_member(uuid) from public,anon;
grant execute on function mylist_private.remove_family_member(uuid) to authenticated;
create or replace function public.mylist_remove_family_member(target_user_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
 select mylist_private.remove_family_member(target_user_id)
$$;
revoke all on function public.mylist_remove_family_member(uuid) from public,anon;
grant execute on function public.mylist_remove_family_member(uuid) to authenticated;
