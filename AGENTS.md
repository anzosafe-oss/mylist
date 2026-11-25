# AGENTS.md — mylist

## Repository scope
- Work directly in `anzosafe-oss/mylist` only. Do not search, list, or inspect other GitHub repositories or organization-wide resources.
- Expand scope only when the user explicitly requests cross-app integration, or after explaining a necessary external dependency and obtaining approval.
- Read this file first. Use known repository paths and targeted code searches; avoid repeated discovery.

## Token efficiency
- Inspect only relevant files, functions, and direct dependencies. Read targeted line ranges where possible.
- Avoid full audits, full-file rewrites, unrelated refactoring, repeated checks, and unnecessary previews or documentation.
- Use the smallest safe patch. Preserve existing UI, behavior, and versioning conventions.
- For Supabase, access only the associated project and app-specific resources relevant to the task. Do not enumerate unrelated apps or expose secrets. Verify unknown resource identifiers before use.

## Maintenance and safety
- Check references before deleting obsolete assets or code, including dynamic references, manifests, service workers, caches and deployment configuration. Never delete uncertain resources or rewrite Git history.
- Keep cleanup targeted; do not perform unsolicited repository-wide cleanup.
- Run tests proportionate to risk, including relevant regressions. Report untested behavior and blockers.
- Prepare application changes on a separate branch; production publication requires explicit user approval.
- Report changed files, test results, limitations and decisions concisely.
