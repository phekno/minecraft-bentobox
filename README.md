# minecraft-bentobox

Two Minecraft server images for the family cluster: **OneBlock** and
**Skyblock**, both built on [itzg/minecraft-server] with
[BentoBox] and its addons baked in and pinned.

```
ghcr.io/phekno/minecraft-oneblock
ghcr.io/phekno/minecraft-skyblock
```

## Why this exists

OneBlock and Skyblock are Paper *plugins*, not Forge mods — the canonical
implementation is BentoBox plus the `AOneBlock` or `BSkyBlock` addon. itzg's
image already handles Paper and syncs baked plugin directories, so all that was
missing was a pinned, tested plugin set with sensible defaults for a handful of
kids.

The plugin set in an image is exactly what its tag says: every jar is verified
against a checksum at build time, and nothing is published until a real server
has booted with every addon reporting `ENABLED`.

## What's inside

| | |
|---|---|
| Base | `ghcr.io/itzg/minecraft-server`, Java 25, digest-pinned |
| Server | Paper, pinned to Minecraft **26.2** |
| Core | BentoBox |
| Both images | Challenges, Border, Level |
| OneBlock only | AOneBlock |
| Skyblock only | BSkyBlock |

Exact versions live in [`plugins.lock`](plugins.lock).

Minecraft **26.2** is pinned because it is the newest version BentoBox lists as
tested and Paper ships a stable build for it. The addons do load on 26.3, but
that is outside BentoBox's tested list, Paper's 26.3 build is alpha, and
BentoBox cannot parse the version (`Running PAPER Invalid`). Bump when BentoBox
lists 26.3.

> Players need a **26.2** client profile for these servers.

## Gameplay defaults

One island per player: a kid joins, an island is created for them, and they are
teleported onto it — no commands to learn. `/island invite` lets siblings co-op,
`/island go` visits. Team size is raised to 6 so everyone can share one island.

Without `create-island-on-first-login` a new player lands in the leftover
vanilla overworld with no island and no idea what to do, which is the single
most common way these servers disappoint a kid.

## Running one

```sh
docker run -d --name oneblock \
  -e EULA=TRUE -e MEMORY=4G \
  -p 25565:25565 \
  -v oneblock-data:/data \
  ghcr.io/phekno/minecraft-oneblock:latest
```

`EULA` is deliberately not baked into the image — accepting it is the
operator's act.

## Tags

| tag | mutable? | use |
|---|---|---|
| `26.2-a1b2c3d` | no | `<minecraft version>-<commit>`, unique per build |
| `sha-<full commit>` | no | the same guarantee, spelled out |
| `latest` | **yes** | convenience only |

Deployments should pin a digest. The image also carries
`com.phekno.minecraft.version` and `com.phekno.minecraft.plugins` labels, so
`docker inspect` tells you exactly what is inside without pulling the tag apart.

## Config

Config files under `common/`, `oneblock/` and `skyblock/` are **seeds**. itzg
copies them into `/data` on first run, and because
`SYNC_SKIP_NEWER_IN_DESTINATION` defaults to true it never overwrites a file the
server or an admin has since changed. Edit in-game or in the volume freely.

The seeds are deliberately partial — only the keys being overridden. BentoBox
fills in every other key and rewrites the full commented file on first boot, so
these stay small and reviewable instead of being 500-line copies that go stale.

`${...}` placeholders in seeded YAML are interpolated from the environment at
sync time, so a value can be exposed to the deployment without a rebuild.

## Development

```sh
# regenerate plugins.lock from the latest upstream releases
hack/update-plugins.sh
hack/update-plugins.sh --check      # CI-style: fail if out of date

# build
podman build --format docker --target oneblock -t minecraft-oneblock:dev .
podman build --format docker --target skyblock -t minecraft-skyblock:dev .

# boot it for real and assert every addon is ENABLED
CONTAINER_ENGINE=podman test/smoke.sh minecraft-oneblock:dev oneblock
CONTAINER_ENGINE=podman test/smoke.sh minecraft-skyblock:dev skyblock
```

`--format docker` matters for podman: the default OCI format drops the base
image's `HEALTHCHECK`.

Version bumps come from a weekly workflow that regenerates `plugins.lock` and
opens a PR. Renovate is not used because it can bump a version string but
cannot maintain the matching checksums.

## Layout

```
Dockerfile              multi-stage; --target oneblock | skyblock
plugins.lock            versions + sha256 for every jar (source of truth)
hack/update-plugins.sh  regenerates the lock from GitHub releases
common/plugins/         config seeds shared by both images
oneblock/plugins/       AOneBlock config seed
skyblock/plugins/       BSkyBlock config seed
test/smoke.sh           boots an image and asserts the addons loaded
```

BentoBox addons must live in `plugins/BentoBox/addons/`, not `plugins/`. Put
them in `plugins/` and Paper tries to load them as ordinary plugins; they fail
with `NoClassDefFoundError: Pladdon` and BentoBox reports `Loaded 0 addons`
while the server otherwise starts up looking perfectly healthy.

[itzg/minecraft-server]: https://github.com/itzg/docker-minecraft-server
[BentoBox]: https://github.com/BentoBoxWorld/BentoBox
