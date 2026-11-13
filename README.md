# MyList v2.0.0

Shopping lists with Supabase password/invitation authentication, private lists, explicit per-list sharing, automatic completion history and restore.

## Hosting

Publish `dist/` as the GitHub Pages artifact. `.github/workflows/pages.yml` handles deployments from main. Sites preview uses `.openai/hosting.json`.

## Supabase

Uses the existing MySubs project (`radskybbymadavveatzn`), isolated `mylist_*` tables and `mylist_private` functions. `supabase/schema.sql` is the initial schema reference: already applied, do not run it again on this project.

`mylist-invite` is an authenticated Edge Function. It verifies the caller through Auth and checks MyList administrator status on the server. Its service role key is supplied only by the Supabase runtime. No secret key belongs in frontend code or this repository.

Add these exact URLs to Authentication > URL Configuration > Redirect URLs, preserving URLs used by other apps:

- https://anzosafe-oss.github.io/mylist/
- https://mylist-anzo-preview.zota-andrei.chatgpt.site/

Email invitations and login links use the project's existing SMTP configuration. A custom SMTP provider must permit mail to invited recipients. Invite no real recipients during testing.

The administrator is bootstrapped from the verified existing owner account. Other accounts need a MyList invitation. An invitation alone grants no list access.

## Data behavior

Every product has a server ID; mutations update only specified fields through an authenticated RPC. Changes on the same list are serialized in a transaction. The last purchased item archives the list. Restoration resets purchases and preserves quantities and sharing.

Visible clients refresh data every 3 seconds and on foreground/reconnection. The app does not accept offline edits; a failed write is shown and is never reported as synchronized. Presence is scoped to the current list.

Legacy browser lists are offered for explicit import in Settings; the source browser data is retained. Imported lists are private and products start unchecked. Exports contain only lists accessible to the signed-in user.

## Build

No build step: `dist/` is the authoritative static application.
Do not run the legacy `build.cjs`, which predates the current frontend.
`npm run check` validates application syntax.

## Verification

Server transaction tests covered private/shared visibility, unrelated accounts, completion, restoration, quantity preservation and access revocation. Test accounts and lists were rolled back.


## Families and AdminMyList (v2.0.0)
Apply `supabase/families.sql` after the existing schema, profile and account-administration upgrades. It preserves the initial four-member household and existing list sharing. All subsequent app-wide invitations create a separate family administrator. Each household has exactly four seats, including its administrator; pending invitations reserve seats. Failed sends release new reservations. Global Auth identities and other applications are not deleted.

The main Settings roster/invitations are restricted to the signed-in household using RLS. Only family administrators send family invitations. AdminMyList at `/admin/` is a separate installable frontend using the same existing MyList session; its authenticated RPC verifies the global admin role in the database. It reports accounts, family administrators, pending/history and seat quotas, and never retrieves shopping lists. Family administrators cannot access it. The AdminMyList manifest has a separate identity, scope and A-marked icon.

The server function verifies the Auth bearer token, then calls a service-role-only reservation RPC, which serializes email/household reservations. Neither client metadata nor client-supplied family IDs grant roles. The legacy internal list function is no longer executable by browser roles. Every list remains private until explicitly shared within its household.

Run `tests/families.sql` against a transaction-capable SQL console: all fixtures roll back and no email is sent. The older `tests/account-administration.sql` documents the pre-family v1.2.0 schema and is superseded by the v2.0.0 suite.

GitHub Pages currently also runs its built-in branch-root publisher. Root `index.html` and `admin/` mirror the authoritative `dist/` entrypoints so either publisher serves the same release. Update both until hosting is switched exclusively to Actions.
