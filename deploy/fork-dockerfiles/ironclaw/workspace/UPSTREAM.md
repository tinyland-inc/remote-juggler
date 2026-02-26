# IronClaw Reference Project Tracking

Repository: tinyland-inc/ironclaw (standalone, based on OpenClaw)
Reference: openclaw/openclaw (monitored for useful patterns and security fixes)

## Current State
- Reference project HEAD: (populated by oc-upstream-sync campaign)
- Our main HEAD: (populated by oc-self-evolve campaign)
- Last reference check: never

## Reference Changes to Evaluate
<!-- Populated by oc-upstream-sync campaign monitoring openclaw/openclaw -->

## Schema Changes
<!-- Track OpenClaw Zod schema changes that affect openclaw.json -->

## Features to Evaluate
<!-- New OpenClaw features worth adopting into our deployment -->

## Our Customizations
- Custom Dockerfile with workspace bootstrap
- openclaw.json with RemoteJuggler-specific config
- Workspace files (AGENTS.md, SOUL.md, IDENTITY.md, TOOLS.md, HEARTBEAT.md, BOOTSTRAP.md, UPSTREAM.md)
- Skills: rj-platform, github-ops, aperture-metering, identity-mgmt
- Cron jobs: reference-check (6h), health-report (4h), memory-maintenance (daily)
