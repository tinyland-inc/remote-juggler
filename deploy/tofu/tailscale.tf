# =============================================================================
# Tailscale ACL Policy + Auth Keys
# =============================================================================
#
# Manages the Tailscale ACL grants that control identity-aware access to
# rj-gateway and setec. Replaces the static tailscale-acl-grants.hujson.
# =============================================================================

resource "tailscale_acl" "remotejuggler" {
  acl = jsonencode({
    grants = [
      {
        # Allow all tailnet members to read secrets via rj-gateway
        src = ["autogroup:member"]
        dst = [local.tailscale_tags.gateway]
        app = {
          "tailscale.com/cap/rj-gateway" = [{ role = "reader" }]
        }
      },
      {
        # Allow admin users to write secrets and view audit logs
        src = ["group:admins"]
        dst = [local.tailscale_tags.gateway]
        app = {
          "tailscale.com/cap/rj-gateway" = [{ role = "admin" }]
        }
      },
      {
        # Allow CI/CD agents to read specific secrets
        src = [local.tailscale_tags.ci_agent]
        dst = [local.tailscale_tags.gateway]
        app = {
          "tailscale.com/cap/rj-gateway" = [{
            role    = "reader"
            secrets = ["github-token", "gitlab-token", "neon-database-url"]
          }]
        }
      },
      {
        # Allow rj-gateway to access setec
        src = [local.tailscale_tags.gateway]
        dst = [local.tailscale_tags.setec]
        app = {
          "tailscale.com/cap/setec" = [{ role = "admin" }]
        }
      },
    ]

    tagOwners = {
      "tag:rj-gateway" = ["autogroup:admin"]
      "tag:setec"       = ["autogroup:admin"]
      "tag:ci-agent"    = ["autogroup:admin"]
      "tag:k8s"         = ["autogroup:admin"]
    }
  })
}

# Ephemeral auth key for services that use the Tailscale operator
resource "tailscale_tailnet_key" "operator" {
  reusable      = true
  ephemeral     = true
  preauthorized = true
  tags          = ["tag:k8s"]
  description   = "OpenTofu-managed key for Tailscale K8s Operator"
}

# Auth key for setec (tagged for ACL matching)
resource "tailscale_tailnet_key" "setec" {
  reusable      = true
  ephemeral     = true
  preauthorized = true
  tags          = ["tag:setec"]
  description   = "OpenTofu-managed key for Setec"
}

# Auth key for rj-gateway (tagged for ACL matching)
resource "tailscale_tailnet_key" "gateway" {
  reusable      = true
  ephemeral     = true
  preauthorized = true
  tags          = ["tag:rj-gateway"]
  description   = "OpenTofu-managed key for rj-gateway"
}

# Auth key for CI agents
resource "tailscale_tailnet_key" "ci_agent" {
  reusable      = true
  ephemeral     = true
  preauthorized = true
  tags          = ["tag:ci-agent"]
  description   = "OpenTofu-managed key for CI agents"
}
