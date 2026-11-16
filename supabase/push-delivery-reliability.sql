-- v2.3.2: terminal attempts no longer keep waking an empty dispatcher.
create or replace function mylist_private.push_tick() returns void language plpgsql security definer set search_path='' as $$
begin
 update public.mylist_push_queue set finished_at=now(),outcome='failed:retry_limit' where finished_at is null and attempts>=5 and (locked_until is null or locked_until<now());
 delete from public.mylist_push_queue where created_at<now()-interval '7 days';
 delete from public.mylist_push_subscriptions s where not exists(select 1 from auth.sessions a where a.id=s.session_id and a.user_id=s.user_id and (a.not_after is null or a.not_after>now())) or not exists(select 1 from public.mylist_accounts a where a.user_id=s.user_id and a.accepted_at is not null);
 if coalesce((select enabled from public.mylist_push_config where id),false) and exists(select 1 from public.mylist_push_queue where finished_at is null and attempts<5 and due_at<=now() and (locked_until is null or locked_until<now())) then
  perform net.http_post(url:='https://radskybbymadavveatzn.supabase.co/functions/v1/mylist-push',headers:=jsonb_build_object('Content-Type','application/json','x-mylist-dispatch',(select keys->>'dispatchToken' from public.mylist_push_config where id)),body:='{"action":"dispatch"}'::jsonb,timeout_milliseconds:=30000);
 end if;
end$$;
revoke all on function mylist_private.push_tick() from public,anon,authenticated;
