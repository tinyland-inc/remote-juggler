# =============================================================================
# IronClaw Agent + Adapter Sidecar + Campaign Runner
# =============================================================================
#
# 3-container pod:
#   1. ironclaw    — real OpenClaw fork (ghcr.io/tinyland-inc/ironclaw)
#   2. adapter     — campaign protocol bridge (POST /campaign, GET /status)
#   3. campaign-runner — scheduler sidecar (reads ConfigMap, dispatches work)
#
# IronClaw uses mcporter bridge skill for MCP tool access to rj-gateway.
# LLM calls route through Aperture for identity-aware metering.
# =============================================================================

resource "kubernetes_deployment" "ironclaw" {
  wait_for_rollout = false

  metadata {
    name      = "ironclaw-agent"
    namespace = kubernetes_namespace.main.metadata[0].name
    labels    = merge(local.labels, { app = "ironclaw-agent", tier = "agent" })
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "ironclaw-agent"
      }
    }

    template {
      metadata {
        labels = merge(local.labels, {
          app  = "ironclaw-agent"
          tier = "agent"
        })
        annotations = {
          "tailscale.com/expose"   = "true"
          "tailscale.com/hostname" = "ironclaw"
        }
      }

      spec {
        image_pull_secrets {
          name = kubernetes_secret.ghcr_pull.metadata[0].name
        }

        security_context {
          fs_group = 10000
        }

        # IronClaw agent container (real OpenClaw fork)
        container {
          name  = "ironclaw"
          image = var.ironclaw_image

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

          env {
            name  = "OPENCLAW_MODEL"
            value = var.ironclaw_model
          }

          env {
            name  = "MCP_SERVERS"
            value = jsonencode({ "rj-gateway" = { url = "http://rj-gateway.${kubernetes_namespace.main.metadata[0].name}.svc.cluster.local:8080/mcp", transport = "http" } })
          }

          env {
            name  = "RJ_GATEWAY_URL"
            value = "http://rj-gateway.${kubernetes_namespace.main.metadata[0].name}.svc.cluster.local:8080"
          }

          env {
            name  = "GIT_AUTHOR_NAME"
            value = "rj-agent-bot[bot]"
          }
          env {
            name  = "GIT_AUTHOR_EMAIL"
            value = var.github_app_id != "" ? "${var.github_app_id}+rj-agent-bot[bot]@users.noreply.github.com" : "ironclaw@fuzzy-dev.tinyland.dev"
          }
          env {
            name  = "GIT_COMMITTER_NAME"
            value = "rj-agent-bot[bot]"
          }
          env {
            name  = "GIT_COMMITTER_EMAIL"
            value = var.github_app_id != "" ? "${var.github_app_id}+rj-agent-bot[bot]@users.noreply.github.com" : "ironclaw@fuzzy-dev.tinyland.dev"
          }
          env {
            name  = "GIT_SSH_COMMAND"
            value = "ssh -i /home/agent/.ssh/id_ed25519 -o StrictHostKeyChecking=no"
          }

          env {
            name = "OPENCLAW_GATEWAY_TOKEN"
            value_from {
              secret_key_ref {
                name     = kubernetes_secret.agent_api_keys.metadata[0].name
                key      = "OPENCLAW_GATEWAY_TOKEN"
                optional = true
              }
            }
          }

          port {
            container_port = 18789
            name           = "chat"
          }

          port {
            container_port = 18790
            name           = "agent"
          }

          volume_mount {
            name       = "workspace"
            mount_path = "/workspace"
          }

          volume_mount {
            name       = "ssh-keys"
            mount_path = "/home/agent/.ssh/id_ed25519"
            sub_path   = "ironclaw-id-ed25519"
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

        # Adapter sidecar — bridges campaign protocol to IronClaw's OpenResponses API
        container {
          name  = "adapter"
          image = var.adapter_image

          args = [
            "--agent-type=ironclaw",
            "--agent-url=http://localhost:18789",
            "--listen-port=8080",
            "--gateway-url=http://rj-gateway.${kubernetes_namespace.main.metadata[0].name}.svc.cluster.local:8080",
          ]

          env {
            name = "ADAPTER_AGENT_AUTH_TOKEN"
            value_from {
              secret_key_ref {
                name     = kubernetes_secret.agent_api_keys.metadata[0].name
                key      = "OPENCLAW_GATEWAY_TOKEN"
                optional = true
              }
            }
          }

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

        # Campaign runner sidecar
        dynamic "container" {
          for_each = var.campaign_runner_enabled ? [1] : []
          content {
            name  = "campaign-runner"
            image = var.campaign_runner_image

            args = [
              "--campaigns-dir=/etc/campaigns",
              "--gateway-url=http://rj-gateway.${kubernetes_namespace.main.metadata[0].name}.svc.cluster.local:8080",
              "--ironclaw-url=http://localhost:8080",
              "--picoclaw-url=http://picoclaw-agent.${kubernetes_namespace.main.metadata[0].name}.svc.cluster.local:8080",
              "--hexstrike-ai-url=http://hexstrike-ai-agent.${kubernetes_namespace.main.metadata[0].name}.svc.cluster.local:8080",
              "--interval=60s",
              "--api-port=8081",
            ]

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

            # GitHub App credentials for bot-attributed Discussions (issue #9).
            # When both are set, campaign runner generates JWT → installation token.
            env {
              name  = "GITHUB_APP_ID"
              value = var.github_app_id
            }

            env {
              name = "GITHUB_APP_PRIVATE_KEY"
              value_from {
                secret_key_ref {
                  name     = kubernetes_secret.agent_api_keys.metadata[0].name
                  key      = "GITHUB_APP_PRIVATE_KEY"
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

        volume {
          name = "campaigns"
          config_map {
            name     = kubernetes_config_map.campaign_definitions.metadata[0].name
            optional = true
          }
        }

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
