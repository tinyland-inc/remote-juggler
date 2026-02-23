# =============================================================================
# rj-gateway — MCP Proxy + Composite Secret Resolver
# =============================================================================
#
# The gateway binary has tsnet embedded, so it joins the tailnet directly.
# No Tailscale sidecar needed — the operator annotation on the service is
# only for DNS registration if desired, but tsnet handles connectivity.
# =============================================================================

resource "kubernetes_deployment" "gateway" {
  wait_for_rollout = false

  metadata {
    name      = "rj-gateway"
    namespace = kubernetes_namespace.main.metadata[0].name
    labels    = merge(local.labels, { app = "rj-gateway" })
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "rj-gateway"
      }
    }

    template {
      metadata {
        labels = merge(local.labels, { app = "rj-gateway" })
      }

      spec {
        container {
          name  = "gateway"
          image = var.gateway_image

          args = ["--config=/etc/rj-gateway/config.json"]

          env {
            name = "TS_AUTHKEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.ts_auth.metadata[0].name
                key  = "TS_AUTHKEY"
              }
            }
          }

          env {
            name  = "TS_HOSTNAME"
            value = "rj-gateway"
          }

          env {
            name  = "TS_STATE_DIR"
            value = "/var/lib/tsnet"
          }

          port {
            container_port = 443
            name           = "https"
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/rj-gateway"
            read_only  = true
          }

          volume_mount {
            name       = "ts-state"
            mount_path = "/var/lib/tsnet"
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

        volume {
          name = "config"
          secret {
            secret_name = kubernetes_secret.gateway_config.metadata[0].name
          }
        }

        volume {
          name = "ts-state"
          empty_dir {}
        }
      }
    }
  }

  depends_on = [helm_release.tailscale_operator]
}
