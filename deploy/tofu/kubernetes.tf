# =============================================================================
# Kubernetes Namespace + Shared Resources
# =============================================================================

resource "kubernetes_namespace" "main" {
  metadata {
    name   = var.namespace
    labels = local.labels
  }
}

# Tailscale auth key secret (shared by operator-managed pods)
resource "kubernetes_secret" "ts_auth" {
  metadata {
    name      = "ts-auth"
    namespace = kubernetes_namespace.main.metadata[0].name
    labels    = local.labels
  }

  data = {
    TS_AUTHKEY = var.tailscale_auth_key
  }
}

# Gateway configuration secret
resource "kubernetes_secret" "gateway_config" {
  metadata {
    name      = "rj-gateway-config"
    namespace = kubernetes_namespace.main.metadata[0].name
    labels    = local.labels
  }

  data = {
    "config.json" = local.gateway_config
  }
}
