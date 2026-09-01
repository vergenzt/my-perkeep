output "url" {
  description = "Perkeep UI URL. Reachable only from your tailnet. <tailnet> is your tailnet's MagicDNS name, e.g. tail1234.ts.net."
  value       = format("%s://%s.<tailnet>.ts.net", var.tailscale_https ? "https" : "http", var.tailscale_hostname)
}

output "project_status" {
  description = "Container Manager project status as reported by DSM."
  value       = synology_container_project.perkeep.status
}

output "config_file" {
  description = "Path to the Terraform-managed server config on the NAS."
  value       = synology_filestation_file.server_config.real_path
}

output "data_dir" {
  description = "Path to the blob store and index on the NAS. Not deleted by `terraform destroy` of the container."
  value       = synology_filestation_folder.data.real_path
}

output "logs_command" {
  description = "Tail the container logs over SSH to find the tsnet login URL and the generated GPG identity."
  value       = "ssh <you>@<nas> sudo docker logs -f ${var.project_name}"
}
