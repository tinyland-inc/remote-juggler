# =============================================================================
# OpenClaw Agent
# =============================================================================
#
# AI agent that routes through Aperture for identity-aware credential access.
# Tailscale Operator handles sidecar injection via service annotation.
# =============================================================================

resource "kubernetes_deployment" "openclaw" {
  wait_for_rollout = false

  metadata {
    name      = "openclaw-agent"
    namespace = kubernetes_namespace.main.metadata[0].name
    labels    = merge(local.labels, { app = "openclaw-agent", tier = "agent" })
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "openclaw-agent"
      }
    }

    template {
      metadata {
        labels = merge(local.labels, {
          app  = "openclaw-agent"
          tier = "agent"
        })
        annotations = {
          # Tailscale Operator injects sidecar for tailnet connectivity
          "tailscale.com/expose"   = "true"
          "tailscale.com/hostname" = "openclaw-agent"
        }
      }

      spec {
        # Single container — operator injects Tailscale sidecar
        container {
          name  = "openclaw"
          image = var.openclaw_image

          env {
            name  = "OPENAI_BASE_URL"
            value = "https://${var.aperture_hostname}/v1"
          }

          env {
            name  = "ANTHROPIC_BASE_URL"
            value = "https://${var.aperture_hostname}/anthropic"
          }

          env {
            name  = "MCP_SERVERS"
            value = jsonencode({ "rj-gateway" = { url = "https://rj-gateway.${var.tailscale_tailnet}/mcp", transport = "http" } })
          }

          volume_mount {
            name       = "workspace"
            mount_path = "/workspace"
          }

          resources {
            requests = {
              cpu    = "200m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1"
              memory = "1Gi"
            }
          }
        }

        volume {
          name = "workspace"
          empty_dir {}
        }
      }
    }
  }

  depends_on = [helm_release.tailscale_operator]
}

# =============================================================================
# HexStrike Pentest Agent
# =============================================================================
#
# Security testing agent — replicas=0 by default, scale up for engagements.
# Requires NET_RAW and NET_ADMIN for network security tools.
# =============================================================================

resource "kubernetes_persistent_volume_claim" "hexstrike_results" {
  wait_until_bound = false

  metadata {
    name      = "hexstrike-results"
    namespace = kubernetes_namespace.main.metadata[0].name
    labels    = merge(local.labels, { app = "hexstrike-agent" })
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.hexstrike_results_storage_size
      }
    }
  }
}

resource "kubernetes_deployment" "hexstrike" {
  wait_for_rollout = false

  metadata {
    name      = "hexstrike-agent"
    namespace = kubernetes_namespace.main.metadata[0].name
    labels    = merge(local.labels, {
      app      = "hexstrike-agent"
      tier     = "agent"
      security = "pentest"
    })
  }

  spec {
    replicas = var.hexstrike_replicas

    selector {
      match_labels = {
        app = "hexstrike-agent"
      }
    }

    template {
      metadata {
        labels = merge(local.labels, {
          app      = "hexstrike-agent"
          tier     = "agent"
          security = "pentest"
        })
        annotations = {
          "tailscale.com/expose"   = "true"
          "tailscale.com/hostname" = "hexstrike-agent"
        }
      }

      spec {
        container {
          name  = "hexstrike"
          image = var.hexstrike_image

          env {
            name  = "ANTHROPIC_BASE_URL"
            value = "https://${var.aperture_hostname}/anthropic"
          }

          env {
            name  = "MCP_SERVER_URL"
            value = "https://rj-gateway.${var.tailscale_tailnet}/mcp"
          }

          volume_mount {
            name       = "workspace"
            mount_path = "/workspace"
          }

          volume_mount {
            name       = "results"
            mount_path = "/results"
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "2"
              memory = "2Gi"
            }
          }

          security_context {
            capabilities {
              add = ["NET_RAW", "NET_ADMIN"]
            }
          }
        }

        volume {
          name = "workspace"
          empty_dir {}
        }

        volume {
          name = "results"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.hexstrike_results.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [helm_release.tailscale_operator]
}
