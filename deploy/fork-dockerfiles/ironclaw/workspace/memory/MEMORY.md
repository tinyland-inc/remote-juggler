# IronClaw Long-Term Memory

## Platform Architecture

- **Cluster**: Civo Kubernetes, namespace `fuzzy-dev`
- **Gateway**: `http://rj-gateway.fuzzy-dev.svc.cluster.local:8080` (51 MCP tools)
- **Aperture**: LLM proxy at `http://aperture.fuzzy-dev.svc.cluster.local`
- **Setec**: Secret store, accessed via `juggler_setec_*` tools
- **Bot**: `rj-agent-bot[bot]` (GitHub App ID 2945224)

## Repository Status

- **Repo**: tinyland-inc/ironclaw (standalone, based on OpenClaw)
- **Reference**: openclaw/openclaw (monitored for useful patterns and security fixes)
- **Customizations**: Dockerfile, openclaw.json config, workspace files, skills, cron jobs
- **Last reference check**: (not yet performed)

## Key URLs

- Gateway health: `http://rj-gateway.fuzzy-dev.svc.cluster.local:8080/health`
- Campaign API: `http://localhost:8081/status`
- Aperture: `http://aperture.fuzzy-dev.svc.cluster.local`

## Campaign Patterns

- Findings format: `__findings__[{...}]__end_findings__`
- Setec keys use bare names (client adds `remotejuggler/` prefix)
- `juggler_resolve_composite` uses `query` parameter
- GitHub tools auto-resolve tokens

## Observations

(This section will be populated by campaign results and heartbeat observations)

## Known Issues

(This section tracks recurring problems and their workarounds)
