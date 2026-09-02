# my-perkeep

[Perkeep](https://perkeep.org) on a Synology NAS, reachable privately over Tailscale.

GitHub Actions builds a `linux/amd64` image of Perkeep v0.12 to GHCR; Terraform
deploys it via the [`synology-community/synology`](https://registry.terraform.io/providers/synology-community/synology/latest)
provider, which drives DSM's Container Manager and File Station APIs directly —
no SSH, no agent on the NAS.

## Prerequisites

- **DSM 7.0+ with Container Manager installed.** Installing it creates the
  `/docker` shared folder that `share_path` defaults to.
- **A DSM administrator account for Terraform.** Container Manager and File
  Station are admin-only APIs; a normal user fails with a permissions error.
- **A Tailscale auth key** — reusable, non-ephemeral. Tagging it (`tag:perkeep`)
  keeps the node out of your personal device list and exempt from key expiry,
  which otherwise silently disconnects a long-running node. Only consumed on
  first boot; the node identity then lives in persisted tsnet state.
- **MagicDNS and HTTPS Certificates enabled** for the tailnet, if you keep
  `tailscale_https = true`. Perkeep fails to start without them.

## Setup

Run the workflow to publish the image, then make the GHCR package public (or add
a registry credential in Container Manager) so the NAS can pull it.

To build by hand instead:

```bash
docker buildx build --platform linux/amd64 \
  --build-arg PERKEEP_VERSION=v0.12 \
  -t ghcr.io/<you>/perkeep:v0.12 --push image
```

`--platform linux/amd64` is not optional on an Apple Silicon Mac.

Then set the variables. Everything is documented in `terraform/variables.tf`;
`nas_host`, `nas_user` and `image` have no usable defaults, and you will likely
want `nas_skip_cert_check = true`, since DSM ships a self-signed certificate.
Keep the secrets — `nas_password`, `tailscale_authkey`, and `nas_otp_secret` if
DSM 2FA is on — out of tfvars and pass them through the environment:

```bash
cd terraform
export SYNOLOGY_PASSWORD='...'
export TF_VAR_tailscale_authkey='tskey-auth-...'
terraform init && terraform apply
```

First boot generates a GPG identity and registers with Tailscale, so give it a
minute. `ssh you@nas.local sudo docker logs -f perkeep` should show:

```
pk-identity: generated new identity ABCD1234EF567890 in /home/keepy/.config/perkeep/identity-secring.gpg
Tailscale tsnet starting for name "perkeep" ...
Tailscale up; state=Running, self=perkeep.tail1234.ts.net
```

## Design notes

### No published ports

Perkeep's `listen: "tailscale"` runs a userspace WireGuard node in-process
(`tsnet`), binding *only* on the tailnet. Consequences worth knowing:

- Nothing is exposed on the NAS's LAN interfaces, and no `NET_ADMIN` or
  `/dev/net/tun` is needed — it stays an unprivileged container.
- **There is no localhost port**, so there is no Docker healthcheck and no way to
  reach the server from the NAS itself. Liveness is judged from the logs.
- Perkeep accepts exactly one listener, so you cannot also bind a LAN port. This
  is all-in on Tailscale.

Auth is `tailscale:` mode — Perkeep asks the local tsnet daemon who the requester
is. Setting `tailscale_auth` to your email rather than `full-access-to-tailnet`
means other tailnet members, including shared-in devices, cannot read your blobs.

### How the GPG identity stays declarative

Perkeep signs schema blobs with a GPG key, and `server-config.json` must name
that key's ID — but the key does not exist until the server first runs, while
Terraform must write the config before that.

So the image ships `pk-identity`, which creates the keyring if absent and prints
its key ID either way. The entrypoint exports it, and the config refers to it
indirectly via Perkeep's `_env` expansion:

```json
"identity": ["_env", "${PERKEEP_IDENTITY}"]
```

Terraform owns a static file; the runtime resolves the one value it cannot know.
The entrypoint refuses to start if the config is missing, rather than falling
back to a generated default Terraform would not track.

### What persists

| Container path        | Contents                                                       |
|-----------------------|----------------------------------------------------------------|
| `/home/keepy/.config` | `server-config.json`, `identity-secring.gpg`, `tsnet-perkeep/` |
| `/data`               | `blobs/` (your data), `index/` (rebuildable)                   |

All of `.config` must persist. Losing `identity-secring.gpg` orphans every blob
you have signed; losing the tsnet state re-registers the server as a *new*
tailnet node, leaving a stale one behind.

**Back up `identity-secring.gpg` and `/data/blobs` separately.** They are not in
Terraform state, and `terraform destroy` deliberately leaves them on disk.

The index uses LevelDB — pure Go, no cgo or external database. Swap it for
`sqlite` in `templates/server-config.json.tftpl` if you prefer; cgo is available
in the build.

## Gotchas

- **Config-only changes need a container restart.** Container Manager does not
  watch bind-mounted files, so editing `server-config.json` applies cleanly in
  Terraform but changes nothing until
  `ssh you@nas.local sudo docker restart perkeep`. The config hash is folded into
  the project's `metadata` so the change is at least visible in the plan.
- **Upgrading**: re-run the workflow with a new `perkeep_version`, bump `image`,
  apply. Back up `/data/blobs` first — index formats change between releases more
  readily than blob formats.

Three things here are unverified against real hardware:

1. **The container runs as root**, matching upstream's image. Synology bind
   mounts and non-root UIDs interact badly, so this is the path of least
   resistance rather than a recommendation. Set `user` on the service to narrow it.
2. **`make.go` fetches the web UI JavaScript from perkeep.org during the build**,
   so builds need network access to that host. Pass `-offline` in the Dockerfile
   for a hermetic build.
3. **`init: true` depends on the compose version** shipped by your DSM release. If
   Container Manager rejects it, drop it from `main.tf`; the only cost is that
   imagemagick thumbnailing subprocesses are reaped less tidily.

Unrelated but worth knowing: Perkeep ships an official Synology **SPK** package
(`misc/docker/synology` upstream) that runs natively without Docker. Different
path from this one, and unmaintained as far as I can tell.
