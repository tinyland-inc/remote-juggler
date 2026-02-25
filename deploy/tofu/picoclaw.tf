# =============================================================================
# PicoClaw Agent + Adapter Sidecar
# =============================================================================
#
# 2-container pod:
#   1. picoclaw — real PicoClaw fork (ghcr.io/tinyland-inc/picoclaw)
#   2. adapter  — campaign protocol bridge with tool proxy (PicoClaw lacks MCP)
#
# The adapter registers rj-gateway's 43 MCP tools in PicoClaw's native
# ToolRegistry format via the tools_proxy, bridging until upstream MCP
# support lands (issue #290).
# =============================================================================

resource "kubernetes_deployment" "picoclaw" {
  wait_for_rollout = false

  metadata {
    name      = "picoclaw-agent"
    namespace = kubernetes_namespace.main.metadata[0].name
    labels    = merge(local.labels, { app = "picoclaw-agent", tier = "agent" })
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "picoclaw-agent"
      }
    }

    template {
      metadata {
        labels = merge(local.labels, {
          app  = "picoclaw-agent"
          tier = "agent"
        })
      }

      spec {
        image_pull_secrets {
          name = kubernetes_secret.ghcr_pull.metadata[0].name
        }

        # PicoClaw agent container
        container {
          name  = "picoclaw"
          image = var.picoclaw_image

          env {
            name = "ANTHROPIC_API_KEY"
            value_from {
              secret_key_ref {
                name     = kubernetes_secret.agent_api_keys.metadata[0].name
                key      = "ANTHROPIC_API_KEY"
                optional = true
              }
            }
          }

          env {
            name  = "ANTHROPIC_BASE_URL"
            value = local.aperture_cluster_url
          }

          port {
            container_port = 18790
            name           = "agent"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
        }

        # Adapter sidecar — bridges campaign protocol to PicoClaw's native API
        container {
          name  = "adapter"
          image = var.adapter_image

          args = [
            "--agent-type=picoclaw",
            "--agent-url=http://localhost:18790",
            "--listen-port=8080",
            "--gateway-url=http://rj-gateway.${kubernetes_namespace.main.metadata[0].name}.svc.cluster.local:8080",
          ]

          port {
            container_port = 8080
            name           = "adapter"
          }

          resources {
            requests = {
              cpu    = "25m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.tailscale_operator]
}

# ClusterIP Service for PicoClaw adapter (campaign runner dispatches here)
resource "kubernetes_service" "picoclaw" {
  metadata {
    name      = "picoclaw-agent"
    namespace = kubernetes_namespace.main.metadata[0].name
    labels    = merge(local.labels, { app = "picoclaw-agent" })
  }

  spec {
    selector = {
      app = "picoclaw-agent"
    }

    port {
      port        = 8080
      target_port = 8080
      name        = "adapter"
    }

    type = "ClusterIP"
  }
}
