# MyList v2.3.0 — Web Push

Status: implemented and staged; no frontend or Edge Function publication yet. Database migration is applied but dormant: no config, subscriptions, jobs or scheduler are active.

## Implementation

- `dist/push.js`: explicit device opt-in, permission prompt inside the user gesture, per-list account preferences, optional checked/unchecked events, permission/support hints, subscription renewal on sign-in and safe account binding.
- `dist/sw.js` and root `sw.js`: encrypted Web Push receipt, persistent duplicate suppression, recipient binding, notification click routing and cleanup on logout. No page cache is introduced.
- `dist/app.js`: narrow settings/session/logout/deep-link hooks. Completed-list links open the matching archive entry and expand products.
- `dist/index.html`, root `index.html`, `package.json`: script integration, scoped notification styling and v2.3.0. Both GitHub Pages entrypoints remain supported.
- `supabase/functions/mylist-push/{index.ts,logic.ts,deno.json,package.json,package-lock.json}`: authenticated subscriptions, VAPID generation, strict provider endpoint allowlist, private server dispatch token, bounded delivery workers, provider 404/410 cleanup, bounded retries.
- `supabase/push-notifications.sql`: additive tables, policies, triggers, RPCs and cleanup. Existing action, authentication and sharing functions are not replaced.
- `tests/push-*.test.mjs`, `tests/push-notifications.sql`: delivery/auth/routing/worker tests and rolled-back database fixtures.

New tables: `mylist_push_config`, `mylist_push_subscriptions`, `mylist_push_preferences`, `mylist_push_list_preferences`, `mylist_push_queue`. Server tables deny access to anon/authenticated roles; only service_role can read keys/subscriptions/jobs. Preference tables enforce own-user and list-access RLS.

Existing tables only gain notification triggers: `mylist_items`, `mylist_lists`, `mylist_members`, `mylist_accounts`. Revocation/removal cleans affected queued notifications and subscriptions.

## Behavior and security

- Shared lists include owned lists with members and lists shared by another person. Personal lists never notify.
- Added product, newly shared list and completion default on; checked/unchecked default off. Own actions never enqueue a delivery to the actor.
- Events group by subscription, list, kind and 10-second time window. Scheduler runs every 10 seconds only invokes the Edge Function when jobs are due (typical delivery delay roughly 2–22 seconds, plus provider delay).
- Atomic 90-second claims prevent concurrent dispatch; stable delivery IDs and worker IndexedDB suppress network retries. At-least-once network transport cannot guarantee global exactly-once delivery.
- Access, active account, session and current preferences are checked when enqueuing AND immediately before sending. Logout unsubscribes the device and clears local recipient binding; stale account payloads cannot display locally.
- Notification lifetime is 5 minutes. A notification already delivered before revocation can remain in the OS; revocation blocks later queued sends. Users should avoid sensitive list names/product names if device lock-screen previews are enabled.
- VAPID private key/dispatch token are generated inside the Edge Function and retained only in server-only storage. No service_role key, private VAPID key or dispatch token enters browser source or logs. Existing Supabase server environment credentials are reused.
- No external messaging service, no test button and no change to header/navigation/themes.

## Release after approval

1. Deploy new Edge Function `mylist-push` with all five source/config/lock files; `verify_jwt:false` because the handler validates user JWTs with `auth.getUser` plus the live database session, or authenticates cron with its private token.
2. Run `supabase/push-release.sql` to activate the scheduler. Until the first legitimate device opt-in, there are no jobs and no dispatch requests.
3. Publish the saved Sites v2.3.0 version and merge the staged GitHub change to main. Do not run `npm run build` (legacy build overwrites dist); use `npm run check`.
4. First authenticated opt-in initializes VAPID/config automatically. No manual Supabase secret setup is required.
5. Verify the published worker and both entrypoint asset paths, then use real shared-list edits from a second account.

## Validation completed

- SQL tests: grouping, event defaults, own/personal exclusions, per-list mute, completion transition, exclusive claims, send-time revalidation, preference RLS, denied secret/subscription/worker access, logout, revocation and account cleanup. All fixtures rolled back; no emails or push requests sent.
- Deno type checking passed using installed pinned dependencies; real web-push encryption/VAPID request generation passed without any network send.
- Node tests: endpoint SSRF protection, app URL restriction, four event payloads, missing auth/live-session denial, public-key-only config, subscription ownership, private worker token, provider expiry/retries, worker duplicate/account/logout filtering and deep links (active/archive/revoked/wrong account).
- Browser fixture: light/dark settings, shared lists from another owner, escaped list names, preference toggles and permission-denied hint. Main login page still loads v2.3.0. Fixture is excluded from release.
- Supabase security advisor: no new warnings/errors from this feature. Informational RLS-without-policy notices on the three server-only tables are intentional deny-by-default.

## Real-device validation required after release

On iOS/iPadOS 16.4+, launch MyList from Home Screen, enable Push through Settings, grant permission, close the app and edit a shared list using another account. Android requires a Push-capable browser and granted permission. Test add/grouped add/share/completion, optional toggles, per-list mute, notification click, logout/account switch and access revocation. OS notification settings, Focus/battery/network restrictions can affect delivery; no guaranteed delivery time is promised.

References reviewed: https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/ ; https://developer.mozilla.org/en-US/docs/Web/API/Push_API ; https://supabase.com/docs/guides/functions/schedule-functions .
