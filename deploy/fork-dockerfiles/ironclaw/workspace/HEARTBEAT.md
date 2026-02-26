# IronClaw Heartbeat Checklist

Runs every 2 hours during 04:00-23:00. Respond HEARTBEAT_OK if all checks pass.

## Quick Health Check
1. Verify AGENTS.md, SOUL.md, IDENTITY.md, TOOLS.md exist in /workspace/
2. Check memory/MEMORY.md has recent entries (not stale >48h)
3. Test MCP connectivity: call juggler_campaign_status()
4. Check /workspace disk usage (warn if >80%)

## If checks fail
- Missing workspace files: restore from /workspace-defaults/
- Stale memory: note in MEMORY.md, cron memory-maintenance will fix
- MCP unreachable: log error, retry next heartbeat

## Cron handles periodic work
Upstream checks (6h), health reports (4h), and memory maintenance (daily)
run as isolated cron sessions -- not heartbeat items. See cron/jobs.json.
