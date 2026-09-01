locals {
  # Paths inside the container.
  container_config_dir         = "/home/keepy/.config"
  container_perkeep_config_dir = "${local.container_config_dir}/perkeep"
  container_data_dir           = "/data"
  container_blob_path          = "/data/blobs"
  container_index_path         = "/data/index/index.leveldb"

  server_config = templatefile("${path.module}/templates/server-config.json.tftpl", {
    tailscale_auth     = var.tailscale_auth
    tailscale_hostname = var.tailscale_hostname
    https              = var.tailscale_https
    blob_path          = local.container_blob_path
    index_path         = local.container_index_path
    pack_related       = var.pack_related
    share_handler      = var.share_handler
  })

  container_env = merge(
    {
      HOME             = "/home/keepy"
      CAMLI_CONFIG_DIR = local.container_perkeep_config_dir
    },
    var.tailscale_authkey == null ? {} : { TS_AUTHKEY = var.tailscale_authkey },
    var.extra_env,
  )
}

########################################
# Directories on the NAS
#
# Container Manager would happily create bind-mount sources itself, but then
# they would be invisible to Terraform. Declaring them means `terraform destroy`
# leaves the data behind deliberately rather than by accident, and the
# real_path outputs save us from hardcoding a /volume1 prefix that may be wrong.
########################################

resource "synology_filestation_folder" "config" {
  path           = "${var.share_path}/config"
  create_parents = true
}

resource "synology_filestation_folder" "data" {
  path           = "${var.share_path}/data"
  create_parents = true
}

########################################
# Server config
#
# CAMLI_CONFIG_DIR points at <config>/perkeep inside the container, so the file
# lands one level below the bind-mount root. The sibling directories of this
# file -- identity-secring.gpg and tsnet-<hostname>/ -- are created at runtime
# and intentionally not managed here: they are generated secrets and node state,
# not configuration.
########################################

resource "synology_filestation_file" "server_config" {
  path           = "${synology_filestation_folder.config.path}/perkeep/server-config.json"
  content        = local.server_config
  create_parents = true
  overwrite      = true

  lifecycle {
    precondition {
      condition     = can(jsondecode(local.server_config))
      error_message = "Rendered server-config.json is not valid JSON. Check templates/server-config.json.tftpl."
    }

    precondition {
      condition     = !(var.tailscale_https && var.tailscale_hostname == "")
      error_message = "tailscale_https requires a hostname so Tailscale can issue a certificate for it."
    }
  }
}

########################################
# The container
#
# No ports are published. Under `listen: "tailscale"` perkeepd runs a userspace
# WireGuard node via tsnet and binds only on the tailnet, so nothing is exposed
# on the NAS's own interfaces and no NET_ADMIN or /dev/net/tun is required.
########################################

resource "synology_container_project" "perkeep" {
  name       = var.project_name
  share_path = var.share_path
  run        = true

  services = {
    perkeep = {
      image          = var.image
      container_name = var.project_name
      restart        = "unless-stopped"

      # perkeepd shells out to imagemagick for thumbnailing; an init process
      # reaps those children instead of letting them accumulate as zombies.
      init = true

      environment = local.container_env

      volumes = [
        {
          type   = "bind"
          source = synology_filestation_folder.config.real_path
          target = local.container_config_dir
          bind   = { create_host_path = true }
        },
        {
          type   = "bind"
          source = synology_filestation_folder.data.real_path
          target = local.container_data_dir
          bind   = { create_host_path = true }
        },
      ]

      logging = {
        driver = "json-file"
        options = {
          max-size = "10m"
          max-file = "3"
        }
      }
    }
  }

  # Container Manager does not watch bind-mounted files, so a config-only change
  # would otherwise apply cleanly and change nothing until the next restart.
  # Folding the config hash into tracked metadata makes the drift visible.
  metadata = {
    server_config_sha256 = sha256(local.server_config)
  }

  depends_on = [synology_filestation_file.server_config]
}
