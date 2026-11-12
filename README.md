# MyList v1.0.0

Shopping lists with Supabase email-link authentication, private lists, explicit per-list sharing, automatic completion history and restore.

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

npm ci --ignore-scripts
npm run build

## Verification

Server transaction tests covered private/shared visibility, unrelated accounts, completion, restoration, quantity preservation and access revocation. Test accounts and lists were rolled back.
