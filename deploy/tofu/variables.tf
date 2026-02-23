# =============================================================================
# Provider credentials (injected via TF_VAR_* from apply.sh)
# =============================================================================

variable "civo_token" {
  description = "Civo API token"
  type        = string
  sensitive   = true
}

variable "tailscale_oauth_client_id" {
  description = "Tailscale OAuth client ID for the operator"
  type        = string
  sensitive   = true
}

variable "tailscale_oauth_client_secret" {
  description = "Tailscale OAuth client secret for the operator"
  type        = string
  sensitive   = true
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key for service nodes"
  type        = string
  sensitive   = true
}

# =============================================================================
# Cluster configuration
# =============================================================================

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "namespace" {
  description = "Kubernetes namespace for all resources"
  type        = string
  default     = "fuzzy-dev"
}

# =============================================================================
# Container images
# =============================================================================

variable "setec_image" {
  description = "Setec server container image"
  type        = string
  default     = "ghcr.io/tailscale/setec:latest"
}

variable "gateway_image" {
  description = "rj-gateway container image"
  type        = string
  default     = "ghcr.io/tinyland-inc/remote-juggler/gateway:latest"
}

variable "openclaw_image" {
  description = "OpenClaw agent container image"
  type        = string
  default     = "ghcr.io/openclaw/openclaw:latest"
}

variable "hexstrike_image" {
  description = "HexStrike pentest agent container image"
  type        = string
  default     = "ghcr.io/hexstrike/hexstrike-ai:latest"
}

variable "chapel_binary_image" {
  description = "Chapel CLI container image (for gateway sidecar)"
  type        = string
  default     = "ghcr.io/tinyland-inc/remote-juggler:latest"
}

# =============================================================================
# Resource sizing
# =============================================================================

variable "setec_storage_size" {
  description = "PVC size for Setec data directory"
  type        = string
  default     = "1Gi"
}

variable "hexstrike_results_storage_size" {
  description = "PVC size for HexStrike results"
  type        = string
  default     = "5Gi"
}

variable "hexstrike_replicas" {
  description = "Number of HexStrike replicas (0 = dormant, 1 = active engagement)"
  type        = number
  default     = 0
}

# =============================================================================
# Gateway configuration
# =============================================================================

variable "gateway_setec_url" {
  description = "URL for Setec server (tailnet hostname)"
  type        = string
  default     = "https://setec.tail1234.ts.net"
}

variable "gateway_setec_prefix" {
  description = "Key prefix for Setec secrets"
  type        = string
  default     = "remotejuggler/"
}

variable "gateway_precedence" {
  description = "Secret resolution precedence order"
  type        = list(string)
  default     = ["env", "sops", "kdbx", "setec"]
}

# =============================================================================
# Tailnet configuration
# =============================================================================

variable "tailscale_tailnet" {
  description = "Tailscale tailnet name (e.g. 'example.com' or org name)"
  type        = string
}

variable "aperture_hostname" {
  description = "Tailscale hostname for the Aperture proxy"
  type        = string
  default     = "aperture.tail1234.ts.net"
}
