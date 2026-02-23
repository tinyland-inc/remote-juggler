# =============================================================================
# Tailscale Kubernetes Operator (Helm)
# =============================================================================
#
# Replaces manual Tailscale sidecar containers in all deployments.
# The operator watches for annotations and injects sidecars automatically.
#
# After deployment:
#   - Services with `tailscale.com/expose: "true"` get tailnet ingress
#   - No public LoadBalancer IPs needed
#   - Auth key rotation handled by the operator
# =============================================================================

resource "helm_release" "tailscale_operator" {
  name             = "tailscale-operator"
  repository       = "https://pkgs.tailscale.com/helmcharts"
  chart            = "tailscale-operator"
  namespace        = "tailscale"
  create_namespace = true

  set_sensitive {
    name  = "oauth.clientId"
    value = var.tailscale_oauth_client_id
  }

  set_sensitive {
    name  = "oauth.clientSecret"
    value = var.tailscale_oauth_client_secret
  }

  set {
    name  = "operatorConfig.defaultTags"
    value = "tag:k8s"
  }
}
