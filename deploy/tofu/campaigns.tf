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
    "oc-weekly-digest.json"      = file("${path.module}/../../test/campaigns/openclaw/oc-weekly-digest.json")
    "oc-issue-triage.json"       = file("${path.module}/../../test/campaigns/openclaw/oc-issue-triage.json")
    "oc-prompt-audit.json"       = file("${path.module}/../../test/campaigns/openclaw/oc-prompt-audit.json")
    "oc-docs-freshness.json"     = file("${path.module}/../../test/campaigns/openclaw/oc-docs-freshness.json")
    "oc-coverage-gaps.json"      = file("${path.module}/../../test/campaigns/openclaw/oc-coverage-gaps.json")
    "oc-license-scan.json"       = file("${path.module}/../../test/campaigns/openclaw/oc-license-scan.json")
    "oc-wiki-update.json"        = file("${path.module}/../../test/campaigns/openclaw/oc-wiki-update.json")
    "hs-cred-exposure.json"      = file("${path.module}/../../test/campaigns/hexstrike/hs-cred-exposure.json")
    "hs-cve-monitor.json"        = file("${path.module}/../../test/campaigns/hexstrike/hs-cve-monitor.json")
    "hs-dep-vuln.json"           = file("${path.module}/../../test/campaigns/hexstrike/hs-dep-vuln.json")
    "xa-audit-completeness.json" = file("${path.module}/../../test/campaigns/cross-agent/xa-audit-completeness.json")
  }
}
