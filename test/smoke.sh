#!/usr/bin/env bash
# Boot an image for real and prove the plugin set actually loaded.
#
# A build can succeed, the jars can be present, and the server can still come
# up with "Loaded 0 addons" -- that is exactly what happened when the addons
# were first placed in plugins/ instead of plugins/BentoBox/addons/. Only
# running the thing catches it, so CI runs this on every build.
#
# Usage: test/smoke.sh <image> <oneblock|skyblock>
# Env:   CONTAINER_ENGINE (default docker), TIMEOUT_SECS (default 300)

set -euo pipefail

cd "$(dirname "$0")/.."

image=${1:?usage: smoke.sh <image> <oneblock|skyblock>}
variant=${2:?usage: smoke.sh <image> <oneblock|skyblock>}
engine=${CONTAINER_ENGINE:-docker}
timeout_secs=${TIMEOUT_SECS:-300}

name="smoke-$variant-$$"
vol="$name-data"

fail() {
  echo "FAIL: $*" >&2
  echo "--- last 100 log lines ---" >&2
  $engine logs "$name" 2>&1 | tail -100 >&2
  exit 1
}

cleanup() {
  $engine rm -f "$name" >/dev/null 2>&1 || true
  $engine volume rm "$vol" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Expected versions come from the lock file, so the test cannot drift from
# what the image was built with.
expect_bentobox=$(awk '$1=="core" && $2=="BentoBox" {print $3}' plugins.lock)
mapfile -t expect_addons < <(awk -v v="$variant" '$1=="common" || $1==v {print $2" "$3}' plugins.lock | sort)
[[ -n "$expect_bentobox" ]] || fail "no BentoBox entry in plugins.lock"
[[ ${#expect_addons[@]} -gt 0 ]] || fail "no addons in plugins.lock for variant $variant"

echo "==> starting $image ($variant)"
$engine run -d --name "$name" \
  -e EULA=TRUE -e MEMORY=1500M \
  -e ENABLE_RCON=true -e RCON_PASSWORD=smoketest \
  -v "$vol:/data" \
  "$image" >/dev/null

echo "==> waiting for server start (up to ${timeout_secs}s)"
deadline=$((SECONDS + timeout_secs))
# Deliberately not `$engine logs | grep -q`: grep -q exits on the first match,
# which SIGPIPEs the logs command, and `set -o pipefail` then reports the whole
# pipeline as failed -- so the loop never notices the server came up. Capture
# first, match second.
while :; do
  logs=$($engine logs "$name" 2>&1 || true)
  case "$logs" in *"Done ("*) break ;; esac
  [[ $SECONDS -lt $deadline ]] || fail "server did not finish starting within ${timeout_secs}s"
  running=$($engine ps --filter "name=$name" --filter status=running --format '{{.Names}}' || true)
  [[ "$running" == *"$name"* ]] || fail "container exited before the server started"
  sleep 5
done

# Strip the colour codes BentoBox writes into RCON output.
version_out=$($engine exec "$name" rcon-cli bentobox version 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
echo "$version_out"

echo "==> checking BentoBox $expect_bentobox"
grep -qE "BentoBox version:[[:space:]]+$expect_bentobox" <<<"$version_out" \
  || fail "BentoBox $expect_bentobox not reported"

echo "==> checking ${#expect_addons[@]} addons are ENABLED"
for entry in "${expect_addons[@]}"; do
  read -r addon version <<<"$entry"
  grep -qE "^$addon[[:space:]]+$version[[:space:]]+\(ENABLED\)" <<<"$version_out" \
    || fail "$addon $version is not ENABLED"
  echo "    ok: $addon $version"
done

# The world name is addon-specific -- AOneBlock makes oneblock_world, BSkyBlock
# makes bskyblock_world -- so assert that some game world was registered rather
# than hardcoding a name per variant.
echo "==> checking a game world was registered"
grep -qE "^[a-z0-9_]+_world \(" <<<"$version_out" \
  || fail "no game world listed in 'bentobox version' output"

echo "==> checking for load failures"
logs=$($engine logs "$name" 2>&1 || true)
if grep -qE "SEVERE|Could not load plugin" <<<"$logs"; then
  echo "--- offending lines ---" >&2
  grep -E "SEVERE|Could not load plugin" <<<"$logs" | head -20 >&2 || true
  fail "server log contains load failures"
fi

echo "==> stopping cleanly"
$engine exec "$name" rcon-cli stop >/dev/null 2>&1 || true
deadline=$((SECONDS + 60))
while :; do
  running=$($engine ps --filter "name=$name" --filter status=running --format '{{.Names}}' || true)
  [[ "$running" == *"$name"* ]] || break
  [[ $SECONDS -lt $deadline ]] || fail "server did not stop within 60s"
  sleep 3
done

echo "PASS: $image ($variant)"
