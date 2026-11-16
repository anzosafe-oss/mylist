-- Run ONLY after approval and deployment of the mylist-push Edge Function.
-- VAPID keys and dispatch token initialize automatically on the first authenticated configuration request.
select cron.schedule('mylist-push','10 seconds','select mylist_private.push_tick()');
-- Emergency pause (preserves subscriptions/preferences):
-- update public.mylist_push_config set enabled=false where id;
-- select cron.unschedule('mylist-push');
