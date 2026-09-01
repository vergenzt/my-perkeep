########################################
# Synology DSM connection
########################################

variable "nas_host" {
  description = "DSM URL, including scheme and port, e.g. https://nas.local:5001"
  type        = string
}

variable "nas_user" {
  description = "DSM user. Needs administrator rights: Container Manager and File Station are admin-only APIs."
  type        = string
}

variable "nas_password" {
  description = "Password for nas_user. Prefer the SYNOLOGY_PASSWORD environment variable over putting this in a tfvars file."
  type        = string
  sensitive   = true
  default     = null
}

variable "nas_otp_secret" {
  description = "Base32 TOTP secret, if the DSM account has 2FA enabled. This is the secret behind the QR code, not a 6-digit code."
  type        = string
  sensitive   = true
  default     = null
}

variable "nas_skip_cert_check" {
  description = "Skip TLS verification when talking to DSM. Usually required, since DSM ships a self-signed certificate."
  type        = bool
  default     = true
}

########################################
# Placement on the NAS
########################################

variable "project_name" {
  description = "Container Manager project name. Also used as the container name."
  type        = string
  default     = "perkeep"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_-]*$", var.project_name))
    error_message = "Docker Compose project names must be lowercase alphanumeric, and may contain - and _."
  }
}

variable "share_path" {
  description = <<-EOT
    Path to the project directory, relative to the volume root -- i.e. starting
    at the shared folder, with no /volume1 prefix. The shared folder must
    already exist; Terraform creates the subdirectories beneath it.
  EOT
  type        = string
  default     = "/docker/perkeep"

  validation {
    condition     = can(regex("^/[^/].*", var.share_path)) && !can(regex("^/volume[0-9]+/", var.share_path))
    error_message = "share_path must start with / and must NOT include a /volumeN prefix (e.g. use /docker/perkeep)."
  }
}

########################################
# Image
########################################

variable "image" {
  description = "Fully qualified Perkeep image reference. Built and pushed by .github/workflows/build-image.yml."
  type        = string
  # Override with your own GHCR path, e.g. ghcr.io/<your-user>/perkeep:v0.12
  default = "ghcr.io/OWNER/perkeep:v0.12"

  validation {
    condition     = !can(regex("(^|/)OWNER/", var.image))
    error_message = "Replace OWNER in the image reference with your GitHub username or org."
  }
}

########################################
# Tailscale
########################################

variable "tailscale_authkey" {
  description = <<-EOT
    Tailscale auth key used to register the node on first boot. Generate at
    https://login.tailscale.com/admin/settings/keys.

    Make it Reusable and Ephemeral=false; a tagged key (e.g. tag:perkeep) keeps
    it out of your personal device list and exempt from key expiry.

    Only consumed on first boot -- the node identity then lives in the persisted
    tsnet state directory. Leave null to register interactively instead, by
    following the login URL that appears in the container logs.
  EOT
  type        = string
  sensitive   = true
  default     = null
}

variable "tailscale_hostname" {
  description = "Tailnet hostname for the node. The UI ends up at https://<hostname>.<tailnet>.ts.net."
  type        = string
  default     = "perkeep"

  validation {
    # A value containing a path separator is interpreted by Perkeep as a state
    # directory rather than a hostname, which would silently not do what you want.
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.tailscale_hostname))
    error_message = "tailscale_hostname must be a DNS label: lowercase alphanumerics and hyphens, no slashes."
  }
}

variable "tailscale_auth" {
  description = <<-EOT
    Who may use the Perkeep instance, enforced by Perkeep against Tailscale
    identity. Either "full-access-to-tailnet" (anyone on your tailnet) or a
    single login email such as "you@example.com".
  EOT
  type        = string
  default     = "full-access-to-tailnet"

  validation {
    condition     = var.tailscale_auth == "full-access-to-tailnet" || can(regex("^[^@[:space:]]+@[^@[:space:]]+$", var.tailscale_auth))
    error_message = "tailscale_auth must be \"full-access-to-tailnet\" or a single login email address."
  }
}

variable "tailscale_https" {
  description = <<-EOT
    Serve HTTPS using a Tailscale-issued certificate on port 443 of the tailnet
    node, instead of plain HTTP on port 80.

    Requires MagicDNS and HTTPS Certificates to be enabled for the tailnet
    (Admin console -> DNS). Perkeep fails to start if they are not.
  EOT
  type        = bool
  default     = true
}

########################################
# Perkeep behaviour
########################################

variable "share_handler" {
  description = "Enable Perkeep's share handler, which serves publicly-shared blobs via unguessable URLs (still only reachable on the tailnet)."
  type        = bool
  default     = true
}

variable "pack_related" {
  description = "Repack related blobs together for faster reads. Recommended, and the upstream default for new servers."
  type        = bool
  default     = true
}

variable "extra_env" {
  description = "Additional environment variables to set on the container, merged over the ones this module sets."
  type        = map(string)
  default     = {}
}
