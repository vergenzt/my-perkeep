# syntax=docker/dockerfile:1.7
#
# Perkeep image for Synology Container Manager (x86_64).
#
# Tracks upstream's Dockerfile (github.com/perkeep/perkeep/Dockerfile) closely,
# adding only pk-identity and an entrypoint that bootstraps the GPG keyring so
# server-config.json can stay fully declarative. See tools/pk-identity.
#
# amd64 only: GitHub's ubuntu runners are amd64, so this builds natively.

ARG GO_VERSION=1.25
ARG PERKEEP_VERSION=v0.12

FROM golang:${GO_VERSION} AS build

ARG PERKEEP_VERSION
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /go/src/perkeep.org
RUN git clone --depth 1 --branch "${PERKEEP_VERSION}" https://github.com/perkeep/perkeep.git .
RUN go mod download

# pk-identity lives inside the perkeep.org module so it can import pkg/jsonsign.
COPY tools/ ./tools/

# make.go fetches the web UI JavaScript from perkeep.org at build time. Pass
# -offline if you need a hermetic build and trust the checked-in UI assets.
RUN go run make.go -v

RUN go build -trimpath -ldflags='-s -w' -o /go/bin/pk-identity ./tools/pk-identity

###########################################################################

FROM debian:trixie-slim

LABEL org.opencontainers.image.title="perkeep" \
      org.opencontainers.image.description="Perkeep server for Synology Container Manager, with Tailscale (tsnet) networking" \
      org.opencontainers.image.source="https://github.com/perkeep/perkeep"

ENV HOME=/home/keepy \
    PATH=/home/keepy/bin:$PATH \
    PK_IN_CONTAINER=1 \
    CAMLI_CONFIG_DIR=/home/keepy/.config/perkeep

# imagemagick and the jpeg/heif tools are exec'd by perkeepd for thumbnailing.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        imagemagick \
        libjpeg-turbo-progs \
        libheif1 \
    && rm -rf /var/lib/apt/lists/*

# pk* covers pk, pk-get, pk-put, pk-mount and our pk-identity.
COPY --from=build /go/bin/pk* /home/keepy/bin/
COPY --from=build /go/bin/perkeepd /home/keepy/bin/

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# /home/keepy/.config holds server-config.json, identity-secring.gpg and the
# tsnet node state -- all three must persist or the server re-registers itself
# on the tailnet as a new node every restart.
# /data holds blobs and the index.
VOLUME ["/home/keepy/.config", "/data"]

# Declared for documentation only. Under `listen: "tailscale"` perkeepd binds
# solely on the tailnet, so none of these are reachable from the NAS host.
EXPOSE 80 443 3179

WORKDIR /home/keepy
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["perkeepd"]
