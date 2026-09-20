# syntax=docker/dockerfile:1
#
# Two images from one context:
#   podman build --target oneblock -t minecraft-oneblock .
#   podman build --target skyblock -t minecraft-skyblock .
#
# The island addon is the only real difference between them, so everything
# else lives in the shared `common` stage and is built once.

# Pinned by digest. 2026.9.1-java25 and 2026.9.1 resolve to the same image; the
# explicit -java25 tag records the intent, because BentoBox 3.23.0 needs
# Java 25+.
ARG BASE_IMAGE=ghcr.io/itzg/minecraft-server:2026.9.1-java25@sha256:e8640538dac5d54c2838d57fa9641e735ad0cf2b71fb0e8a68da3b542a315749


# --- fetch -------------------------------------------------------------
# Downloads every jar named in plugins.lock and verifies it. A checksum
# mismatch fails the build, so the jars in an image tag are exactly the ones
# the lock file describes.
FROM docker.io/library/alpine:3.22 AS fetch
RUN apk add --no-cache curl
WORKDIR /jars
COPY plugins.lock ./
RUN set -eu; \
    while read -r scope name version file sha url; do \
      case "$scope" in ''|'#'*) continue ;; esac; \
      echo "fetching $name $version"; \
      mkdir -p "$scope"; \
      curl -fsSL --retry 3 -o "$scope/$file" "$url"; \
      echo "$sha  $scope/$file" | sha256sum -c -; \
    done < plugins.lock; \
    rm plugins.lock


# --- common ------------------------------------------------------------
# itzg syncs /plugins into /data/plugins at startup. Because
# SYNC_SKIP_NEWER_IN_DESTINATION defaults to true, anything here seeds a fresh
# volume but never overwrites a file the server or an admin has since changed.
FROM ${BASE_IMAGE} AS common

# BentoBox is a plugin; its addons live under plugins/BentoBox/addons/.
COPY --from=fetch /jars/core/ /plugins/
COPY --from=fetch /jars/common/ /plugins/BentoBox/addons/
COPY common/plugins/ /plugins/

# 26.2 is the newest version BentoBox 3.23.0 lists as tested, and Paper ships a
# stable build for it. 26.3 exists and the addons do load on it, but it is
# outside that list, Paper's build is alpha, and BentoBox cannot parse the
# version ("Running PAPER Invalid"). Bump when BentoBox lists 26.3.
ENV TYPE=PAPER \
    VERSION=26.2 \
    USE_AIKAR_FLAGS=true

# EULA is deliberately not set. Accepting it is the operator's act and belongs
# in the deployment, not baked into a published image.


# --- oneblock ----------------------------------------------------------
FROM common AS oneblock
COPY --from=fetch /jars/oneblock/ /plugins/BentoBox/addons/
COPY oneblock/plugins/ /plugins/
ENV MOTD="Phekno's OneBlock Server"


# --- skyblock ----------------------------------------------------------
FROM common AS skyblock
COPY --from=fetch /jars/skyblock/ /plugins/BentoBox/addons/
COPY skyblock/plugins/ /plugins/
ENV MOTD="Phekno's Skyblock Server"
