# =============================================================================
# Outputs
# =============================================================================

output "namespace" {
  description = "Kubernetes namespace for all resources"
  value       = kubernetes_namespace.main.metadata[0].name
}

output "setec_service" {
  description = "Setec ClusterIP service name"
  value       = kubernetes_service.setec.metadata[0].name
}

output "setec_tailnet_hostname" {
  description = "Setec tailnet hostname (set via operator annotation)"
  value       = "setec.${var.tailscale_tailnet}"
}

output "gateway_tailnet_hostname" {
  description = "rj-gateway tailnet hostname (set via tsnet)"
  value       = "rj-gateway.${var.tailscale_tailnet}"
}

output "gateway_health_url" {
  description = "Gateway health check URL"
  value       = "https://rj-gateway.${var.tailscale_tailnet}/health"
}

output "openclaw_tailnet_hostname" {
  description = "OpenClaw agent tailnet hostname"
  value       = "openclaw-agent.${var.tailscale_tailnet}"
}

output "hexstrike_tailnet_hostname" {
  description = "HexStrike agent tailnet hostname"
  value       = "hexstrike-agent.${var.tailscale_tailnet}"
}

output "hexstrike_replicas" {
  description = "Current HexStrike replica count"
  value       = var.hexstrike_replicas
}

output "tailscale_operator_status" {
  description = "Tailscale Operator Helm release status"
  value       = helm_release.tailscale_operator.status
}
