---
name: rj-platform
description: RemoteJuggler platform integration for credential resolution, secret management, and audit trails
version: "1.0"
tags: [credentials, secrets, audit, platform]
---

# RemoteJuggler Platform Integration

Use this skill when you need to interact with the RemoteJuggler credential and secret management platform.

## Credential Resolution
- `juggler_resolve_composite(query="<secret-name>")` resolves a secret from multiple backends (env, SOPS, KDBX, Setec) with configurable precedence
- The `query` parameter accepts secret names like `github-token`, `anthropic-api-key`, `brave-api-key`
- Sources are checked in precedence order; the first match wins

## Secret Store (Setec)
- `juggler_setec_list()` lists all available secrets
- `juggler_setec_get(name="<bare-name>")` retrieves a secret value. Use bare names without `remotejuggler/` prefix
- `juggler_setec_put(name="<bare-name>", value="<value>")` stores a secret. Use bare names

## Audit Trail
- `juggler_audit_log(count=20)` retrieves recent credential access entries
- Each entry shows: caller identity, action, query, source, and whether access was allowed
- Use this to verify credential access patterns and detect anomalies

## Campaign Status
- `juggler_campaign_status()` lists all campaign results
- `juggler_campaign_status(campaign_id="oc-dep-audit")` gets results for a specific campaign

## Key Gotchas
- `juggler_resolve_composite` uses `query` parameter, NOT `name`
- `juggler_setec_put`/`get` use `name` parameter with bare names (client adds `remotejuggler/` prefix)
- All operations are audit-logged automatically
