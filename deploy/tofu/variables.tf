# =============================================================================
# Provider credentials (injected via TF_VAR_* from apply.sh)
# =============================================================================

variable "civo_token" {
  description = "Civo API token"
  type        = string
  sensitive   = true
}

variable "tailscale_oauth_client_id" {
  description = "Tailscale OAuth client ID for the operator and provider auth"
  type        = string
  sensitive   = true
}

variable "tailscale_oauth_client_secret" {
  description = "Tailscale OAuth client secret for the operator and provider auth"
  type        = string
  sensitive   = true
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key for service nodes"
  type        = string
  sensitive   = true
}

# =============================================================================
# Agent credentials (seeded into Setec for runtime resolution)
# =============================================================================

variable "github_token" {
  description = "GitHub PAT for API access (seeded into Setec as github-token)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "gitlab_token" {
  description = "GitLab PAT for API access (seeded into Setec as gitlab-token)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "anthropic_api_key" {
  description = "Anthropic API key for agent AI backends (seeded into Setec as anthropic-api-key)"
  type        = string
  sensitive   = true
  default     = ""
}

# =============================================================================
# Container registry (GHCR - all images private)
# =============================================================================

variable "ghcr_username" {
  description = "GitHub username for GHCR image pulls"
  type        = string
  default     = "tinyland-inc"
}

variable "ghcr_token" {
  description = "GitHub PAT or GITHUB_TOKEN with read:packages scope for GHCR pulls"
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
  description = "Setec server container image (built from tailscale/setec source)"
  type        = string
  default     = "ghcr.io/tinyland-inc/remote-juggler/setec:latest" # renovate: image
}

variable "gateway_image" {
  description = "rj-gateway container image"
  type        = string
  default     = "ghcr.io/tinyland-inc/remote-juggler/gateway:latest" # renovate: image
}

variable "openclaw_image" {
  description = "OpenClaw agent container image"
  type        = string
  default     = "ghcr.io/tinyland-inc/remote-juggler/openclaw:latest" # renovate: image
}

variable "hexstrike_image" {
  description = "HexStrike pentest agent container image"
  type        = string
  default     = "ghcr.io/tinyland-inc/remote-juggler/hexstrike:latest" # renovate: image
}

variable "chapel_binary_image" {
  description = "Chapel CLI container image (for gateway sidecar)"
  type        = string
  default     = "ghcr.io/tinyland-inc/remote-juggler:latest"
}

variable "campaign_runner_image" {
  description = "Campaign runner sidecar image (OpenClaw pod)"
  type        = string
  default     = "ghcr.io/tinyland-inc/remote-juggler/campaign-runner:latest" # renovate: image
}

variable "campaign_runner_enabled" {
  description = "Enable campaign runner sidecar on OpenClaw pod (requires image to be built)"
  type        = bool
  default     = true
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
  description = "URL for Setec server (tailnet hostname). Override if Tailscale Operator appends a suffix."
  type        = string
  default     = ""
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
