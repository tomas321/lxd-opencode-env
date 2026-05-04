#!/usr/bin/env bash
set -euo pipefail

PROJECT="${AICODER_PROJECT:-aicoder}"
BRIDGE="${AICODER_BRIDGE:-aicoderbr0}"
PROFILE="${AICODER_PROFILE:-aicoder}"
POOL="${AICODER_POOL:-default}"

command -v lxc >/dev/null || { echo "Missing lxc command"; exit 1; }
command -v jq >/dev/null || { echo "Missing jq command"; exit 1; }

exists_project() {
  lxc project list --format json | jq -r '.[].name' | grep -Fxq "$1"
}

exists_network() {
  lxc network list --format json | jq -r '.[].name' | grep -Fxq "$1"
}

exists_profile() {
  lxc profile list --format json | jq -r '.[].name' | grep -Fxq "$1"
}

# Managed bridge must be created in default project.
lxc project switch default

if ! exists_network "$BRIDGE"; then
  lxc network create "$BRIDGE" --type=bridge \
    ipv4.address=auto \
    ipv4.nat=true \
    ipv6.address=none
fi

if ! exists_project "$PROJECT"; then
  lxc project create "$PROJECT" \
    -c features.images=true \
    -c features.networks=false \
    -c features.profiles=true \
    -c features.storage.volumes=true
fi

lxc project switch "$PROJECT"

if ! exists_profile "$PROFILE"; then
  lxc profile create "$PROFILE"
fi

cat <<EOF | lxc profile edit "$PROFILE"
config: {}
description: AICoder VM profile
devices:
  eth0:
    name: eth0
    nictype: bridged
    parent: ${BRIDGE}
    type: nic
  root:
    path: /
    pool: ${POOL}
    type: disk
name: ${PROFILE}
used_by: []
EOF

echo "Ready."
echo "Project: $PROJECT"
echo "Bridge:  $BRIDGE"
echo "Profile: $PROFILE"
