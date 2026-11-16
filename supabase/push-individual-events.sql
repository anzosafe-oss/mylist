-- v2.3.1: one queue entry per recipient and actual event; no time-window grouping.
create sequence public.mylist_push_event_seq;
revoke all on sequence public.mylist_push_event_seq from public,anon,authenticated;
grant usage,select on sequence public.mylist_push_event_seq to service_role;
create or replace function mylist_private.push_event() returns trigger language plpgsql security definer set search_path='' as $$
declare lid uuid; v_kind text; item_name text:=''; recipient uuid; win bigint:=nextval('public.mylist_push_event_seq'); actor uuid:=auth.uid();
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
 select s.id,lid,v_kind,win,left(item_name,160),clock_timestamp()
 from public.mylist_push_subscriptions s
 where s.user_id<>actor and (recipient is null or s.user_id=recipient)
 and mylist_private.push_allowed(s.user_id,lid,v_kind,s.session_id)
;
 return new;
end$$;
