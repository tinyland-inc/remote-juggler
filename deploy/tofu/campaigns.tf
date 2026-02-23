# =============================================================================
# Campaign Framework Resources
# =============================================================================
#
# ConfigMap for campaign definitions, mounted into the campaign-runner sidecar
# on the OpenClaw pod. Campaign runner reads these at startup and evaluates
# triggers on an interval.
# =============================================================================

resource "kubernetes_config_map" "campaign_definitions" {
  metadata {
    name      = "campaign-definitions"
    namespace = kubernetes_namespace.main.metadata[0].name
    labels    = merge(local.labels, { app = "campaign-runner" })
  }

  data = {
    "index.json"                 = file("${path.module}/../../test/campaigns/index.json")
    "cc-mcp-regression.json"     = file("${path.module}/../../test/campaigns/claude-code/cc-mcp-regression.json")
    "cc-gateway-health.json"     = file("${path.module}/../../test/campaigns/claude-code/cc-gateway-health.json")
    "oc-gateway-smoketest.json"  = file("${path.module}/../../test/campaigns/openclaw/oc-gateway-smoketest.json")
    "oc-dep-audit.json"          = file("${path.module}/../../test/campaigns/openclaw/oc-dep-audit.json")
    "xa-audit-completeness.json" = file("${path.module}/../../test/campaigns/cross-agent/xa-audit-completeness.json")
  }
}
