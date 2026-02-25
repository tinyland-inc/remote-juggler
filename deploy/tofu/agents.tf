# =============================================================================
# OpenClaw Agent + Campaign Runner Sidecar
# =============================================================================
#
# AI agent that routes through Aperture for identity-aware credential access.
# Campaign runner sidecar reads campaign definitions from a mounted ConfigMap,
# evaluates triggers, and dispatches work to agents via rj-gateway MCP.
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
        image_pull_secrets {
          name = kubernetes_secret.ghcr_pull.metadata[0].name
        }

        # Ensure secret volume files are readable by the agent user (UID/GID 10000)
        security_context {
          fs_group = 10000
        }

        # OpenClaw agent container
        container {
          name  = "openclaw"
          image = var.openclaw_image

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

          # Route LLM calls through Aperture for identity-linked attribution.
          # Agents still use their own ANTHROPIC_API_KEY, but Aperture intercepts
          # the request, logs usage against their Tailscale identity, and proxies
          # to the upstream provider.
          env {
            name  = "ANTHROPIC_BASE_URL"
            value = local.aperture_cluster_url
          }

          # Model selection (Aperture must grant access to the requested model)
          env {
            name  = "OPENCLAW_MODEL"
            value = var.openclaw_model
          }

          env {
            name  = "MCP_SERVERS"
            value = jsonencode({ "rj-gateway" = { url = "http://rj-gateway.${kubernetes_namespace.main.metadata[0].name}.svc.cluster.local:8080/mcp", transport = "http" } })
          }

          # In-cluster gateway URL for the OpenClaw Python agent (agent.py).
          env {
            name  = "RJ_GATEWAY_URL"
            value = "http://rj-gateway.${kubernetes_namespace.main.metadata[0].name}.svc.cluster.local:8080"
          }

          # Git identity for attributable commits/PRs.
          # Uses GitHub App bot noreply email for proper attribution when
          # rj-agent-bot GitHub App is installed. Format: {APP_ID}+rj-agent-bot[bot]@users.noreply.github.com
          env {
            name  = "GIT_AUTHOR_NAME"
            value = "rj-agent-bot[bot]"
          }
          env {
            name  = "GIT_AUTHOR_EMAIL"
            value = var.github_app_id != "" ? "${var.github_app_id}+rj-agent-bot[bot]@users.noreply.github.com" : "openclaw@fuzzy-dev.tinyland.dev"
          }
          env {
            name  = "GIT_COMMITTER_NAME"
            value = "rj-agent-bot[bot]"
          }
          env {
            name  = "GIT_COMMITTER_EMAIL"
            value = var.github_app_id != "" ? "${var.github_app_id}+rj-agent-bot[bot]@users.noreply.github.com" : "openclaw@fuzzy-dev.tinyland.dev"
          }
          env {
            name  = "GIT_SSH_COMMAND"
            value = "ssh -i /home/agent/.ssh/id_ed25519 -o StrictHostKeyChecking=no"
          }

          port {
            container_port = 8080
            name           = "agent"
          }

          volume_mount {
            name       = "workspace"
            mount_path = "/workspace"
          }

          volume_mount {
            name       = "ssh-keys"
            mount_path = "/home/agent/.ssh/id_ed25519"
            sub_path   = "openclaw-id-ed25519"
            read_only  = true
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

        # Campaign runner sidecar — orchestrates test campaigns
        # Gated on campaign_runner_enabled (image must be built first)
        dynamic "container" {
          for_each = var.campaign_runner_enabled ? [1] : []
          content {
            name  = "campaign-runner"
            image = var.campaign_runner_image

            args = [
              "--campaigns-dir=/etc/campaigns",
              "--gateway-url=http://rj-gateway.${kubernetes_namespace.main.metadata[0].name}.svc.cluster.local:8080",
              "--hexstrike-url=http://hexstrike-agent.${kubernetes_namespace.main.metadata[0].name}.svc.cluster.local:8080",
              "--interval=60s",
              "--api-port=8081",
            ]

            # GitHub token for feedback handler (issue creation) and publisher (Discussions).
            # Resolved from Setec via apply.sh.
            env {
              name = "GITHUB_TOKEN"
              value_from {
                secret_key_ref {
                  name     = kubernetes_secret.agent_api_keys.metadata[0].name
                  key      = "GITHUB_TOKEN"
                  optional = true
                }
              }
            }

            env {
              name  = "GITHUB_REPO_OWNER"
              value = "tinyland-inc"
            }

            env {
              name  = "GITHUB_REPO_NAME"
              value = "remote-juggler"
            }

            port {
              container_port = 8081
              name           = "api"
            }

            volume_mount {
              name       = "campaigns"
              mount_path = "/etc/campaigns"
              read_only  = true
            }

            resources {
              requests = {
                cpu    = "50m"
                memory = "64Mi"
              }
              limits = {
                cpu    = "200m"
                memory = "128Mi"
              }
            }
          }
        }

        volume {
          name = "workspace"
          empty_dir {}
        }

        # Campaign definitions ConfigMap (always mounted, used when sidecar is enabled)
        volume {
          name = "campaigns"
          config_map {
            name     = kubernetes_config_map.campaign_definitions.metadata[0].name
            optional = true
          }
        }

        # Agent SSH identity keys (for git clone/push operations)
        volume {
          name = "ssh-keys"
          secret {
            secret_name  = kubernetes_secret.agent_ssh_keys.metadata[0].name
            default_mode = "0600"
            optional     = true
          }
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
    labels = merge(local.labels, {
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
        image_pull_secrets {
          name = kubernetes_secret.ghcr_pull.metadata[0].name
        }

        # Ensure secret volume files are readable by the agent user (UID/GID 10000)
        security_context {
          fs_group = 10000
        }

        container {
          name  = "hexstrike"
          image = var.hexstrike_image

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

          # Route LLM calls through Aperture (same as OpenClaw).
          env {
            name  = "ANTHROPIC_BASE_URL"
            value = local.aperture_cluster_url
          }

          # Model selection (Aperture must grant access to the requested model)
          env {
            name  = "HEXSTRIKE_MODEL"
            value = var.hexstrike_model
          }

          # In-cluster gateway URL (HTTP, no TLS needed inside the cluster).
          env {
            name  = "RJ_GATEWAY_URL"
            value = "http://rj-gateway.${kubernetes_namespace.main.metadata[0].name}.svc.cluster.local:8080"
          }

          env {
            name  = "MCP_SERVER_URL"
            value = "http://rj-gateway.${kubernetes_namespace.main.metadata[0].name}.svc.cluster.local:8080/mcp"
          }

          # Git identity for attributable commits/PRs.
          # Uses GitHub App bot noreply email for proper attribution.
          env {
            name  = "GIT_AUTHOR_NAME"
            value = "rj-agent-bot[bot]"
          }
          env {
            name  = "GIT_AUTHOR_EMAIL"
            value = var.github_app_id != "" ? "${var.github_app_id}+rj-agent-bot[bot]@users.noreply.github.com" : "hexstrike@fuzzy-dev.tinyland.dev"
          }
          env {
            name  = "GIT_COMMITTER_NAME"
            value = "rj-agent-bot[bot]"
          }
          env {
            name  = "GIT_COMMITTER_EMAIL"
            value = var.github_app_id != "" ? "${var.github_app_id}+rj-agent-bot[bot]@users.noreply.github.com" : "hexstrike@fuzzy-dev.tinyland.dev"
          }
          env {
            name  = "GIT_SSH_COMMAND"
            value = "ssh -i /home/agent/.ssh/id_ed25519 -o StrictHostKeyChecking=no"
          }

          volume_mount {
            name       = "workspace"
            mount_path = "/workspace"
          }

          volume_mount {
            name       = "results"
            mount_path = "/results"
          }

          volume_mount {
            name       = "ssh-keys"
            mount_path = "/home/agent/.ssh/id_ed25519"
            sub_path   = "hexstrike-id-ed25519"
            read_only  = true
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

        # Agent SSH identity keys (for git clone/push operations)
        volume {
          name = "ssh-keys"
          secret {
            secret_name  = kubernetes_secret.agent_ssh_keys.metadata[0].name
            default_mode = "0600"
            optional     = true
          }
        }
      }
    }
  }

  depends_on = [helm_release.tailscale_operator]
}

# =============================================================================
# HexStrike K8s Service
# =============================================================================
#
# ClusterIP service for HexStrike agent HTTP API. Required because the campaign
# runner (sidecar in OpenClaw pod) dispatches to hexstrike via K8s service URL,
# not localhost.
# =============================================================================

resource "kubernetes_service" "hexstrike" {
  metadata {
    name      = "hexstrike-agent"
    namespace = kubernetes_namespace.main.metadata[0].name
    labels    = merge(local.labels, { app = "hexstrike-agent" })
  }

  spec {
    selector = {
      app = "hexstrike-agent"
    }

    port {
      port        = 8080
      target_port = 8080
      name        = "agent"
    }

    type = "ClusterIP"
  }
}
