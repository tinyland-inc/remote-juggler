# =============================================================================
# Tailscale Auth Keys
# =============================================================================
#
# IMPORTANT: The tailnet ACL policy is NOT managed here. The tailscale_acl
# resource is a destructive singleton that overwrites the ENTIRE tailnet
# policy. ACL grants for RemoteJuggler should be added manually via the
# Tailscale admin console or merged into the tailnet's existing policy.
#
# Reference grants are in: deploy/tailscale-acl-grants.hujson
#
# Tags (tag:rj-gateway, tag:setec, tag:ci-agent, tag:k8s) must be defined
# in the tailnet ACL tagOwners before auth keys below will work.
# =============================================================================

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
