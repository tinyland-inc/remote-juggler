# =============================================================================
# RemoteJuggler Infrastructure — OpenTofu Root Module
# =============================================================================
#
# Manages the RemoteJuggler deployment stack on Civo Kubernetes:
#   - Tailscale Operator (Helm) for tailnet-only ingress
#   - Setec secret server
#   - rj-gateway MCP proxy
#   - OpenClaw + HexStrike AI agents
#
# Usage:
#   ./apply.sh init
#   ./apply.sh plan
#   ./apply.sh apply
#
# All secrets are resolved via rj-gateway (dogfooding).
# =============================================================================

provider "civo" {
  token = var.civo_token
}

provider "tailscale" {
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
  tailnet             = var.tailscale_tailnet
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

# =============================================================================
# Locals
# =============================================================================

locals {
  labels = {
    "app.kubernetes.io/managed-by" = "opentofu"
    "app.kubernetes.io/part-of"    = "remotejuggler"
  }

  tailscale_tags = {
    gateway  = "tag:rj-gateway"
    setec    = "tag:setec"
    ci_agent = "tag:ci-agent"
  }

  # Setec URL: use override if set, otherwise derive from tailnet.
  # Tailscale Operator may append a suffix (e.g. setec -> setec-1).
  effective_setec_url = var.gateway_setec_url != "" ? var.gateway_setec_url : "https://setec.${var.tailscale_tailnet}"

  # Gateway config JSON (mounted as secret)
  gateway_config = jsonencode({
    listen         = ":443"
    chapel_binary  = "remote-juggler"
    setec_url      = local.effective_setec_url
    setec_prefix   = var.gateway_setec_prefix
    setec_secrets  = ["neon-database-url", "github-token", "gitlab-token", "attic-token", "anthropic-api-key"]
    precedence     = var.gateway_precedence
    tailscale = {
      hostname  = "rj-gateway"
      state_dir = "/var/lib/rj-gateway/tsnet"
    }
  })
}
