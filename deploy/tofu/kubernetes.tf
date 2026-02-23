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

# GHCR image pull secret (all images are private)
resource "kubernetes_secret" "ghcr_pull" {
  metadata {
    name      = "ghcr-pull"
    namespace = kubernetes_namespace.main.metadata[0].name
    labels    = local.labels
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          auth = base64encode("${var.ghcr_username}:${var.ghcr_token}")
        }
      }
    })
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
