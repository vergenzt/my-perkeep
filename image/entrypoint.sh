#!/bin/sh
#
# Resolves the pieces of Perkeep's config that cannot be known ahead of time,
# then hands off to perkeepd.
#
# Terraform writes server-config.json before this container has ever run, so it
# cannot know the GPG key ID. Instead the config refers to the identity as
# ["_env", "${PERKEEP_IDENTITY}"], and we fill that in here from the keyring --
# generating the keyring on first boot.

set -eu

CONFIG_DIR="${CAMLI_CONFIG_DIR:-$HOME/.config/perkeep}"
SECRING="${CAMLI_SECRET_RING:-$CONFIG_DIR/identity-secring.gpg}"
CONFIG_FILE="$CONFIG_DIR/server-config.json"

mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_FILE" ]; then
    cat >&2 <<EOF
perkeep: no server config at $CONFIG_FILE

The config is managed by Terraform and bind-mounted in. Either the bind mount
for /home/keepy/.config is wrong, or 'terraform apply' has not run yet.

Refusing to start rather than letting perkeepd generate a throwaway default
config that Terraform does not know about.
EOF
    exit 1
fi

PERKEEP_IDENTITY="$(pk-identity "$SECRING")"
PERKEEP_SECRING="$SECRING"
export PERKEEP_IDENTITY PERKEEP_SECRING

echo "perkeep: identity ${PERKEEP_IDENTITY} (keyring ${SECRING})"

if [ -n "${TS_AUTHKEY:-}" ]; then
    echo "perkeep: TS_AUTHKEY is set; tsnet will register non-interactively"
else
    echo "perkeep: TS_AUTHKEY is unset; watch the logs for a tailscale login URL"
fi

exec "$@"
