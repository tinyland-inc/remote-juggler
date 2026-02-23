terraform {
  required_version = ">= 1.6.0"

  required_providers {
    civo = {
      source  = "civo/civo"
      version = "~> 1.1"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  backend "s3" {
    bucket                      = "rj-tofu-state"
    key                         = "remotejuggler/terraform.tfstate"
    region                      = "LON1"
    endpoint                    = "objectstore.lon1.civo.com"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}
