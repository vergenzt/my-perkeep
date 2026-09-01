terraform {
  required_version = ">= 1.6.0"

  required_providers {
    synology = {
      source  = "synology-community/synology"
      version = "~> 0.6.11"
    }
  }
}

provider "synology" {
  host            = var.nas_host
  user            = var.nas_user
  password        = var.nas_password
  otp_secret      = var.nas_otp_secret
  skip_cert_check = var.nas_skip_cert_check

  # DSM invalidates sessions aggressively; caching avoids re-authenticating
  # (and re-consuming a TOTP step) on every plan.
  session_cache = {
    mode = "file"
    path = pathexpand("~/.cache/terraform-synology")
  }
}
