#!/usr/bin/env bash
set -euo pipefail

PROJECT="${AICODER_PROJECT:-aicoder}"
PROFILE="${AICODER_PROFILE:-aicoder}"
BRIDGE="${AICODER_BRIDGE:-aicoderbr0}"
IMAGE="${AICODER_IMAGE:-aicoder-debian-trixie}"
NAME_PREFIX="${AICODER_NAME_PREFIX:-aicoder}"
CPUS="${AICODER_CPUS:-4}"
MEMORY="${AICODER_MEMORY:-8GiB}"
DISK="${AICODER_DISK:-40GiB}"
STATIC_RANDOM_IP="${AICODER_STATIC_RANDOM_IP:-1}"
UPDATE_HOSTS="${AICODER_UPDATE_HOSTS:-1}"
HOSTS_FILE="${AICODER_HOSTS_FILE:-/etc/hosts}"
SSH_USER="${AICODER_SSH_USER:-coder}"

MOUNTS=()
NAME=""

usage() {
  cat <<EOF
Usage:
  $0 [-n name] [-m /host/path:/vm/path[:ro]]

Examples:
  $0
  $0 -n codex-work
  $0 -m /home/me/project:/workspace
  $0 -m /home/me/project:/workspace -m /tmp/data:/data:ro
EOF
}

while getopts ":n:m:h" opt; do
  case "$opt" in
    n) NAME="$OPTARG" ;;
    m) MOUNTS+=("$OPTARG") ;;
    h) usage; exit 0 ;;
    :) echo "Missing argument for -$OPTARG"; exit 1 ;;
    \?) echo "Unknown option: -$OPTARG"; usage; exit 1 ;;
  esac
done

command -v lxc >/dev/null || { echo "Missing lxc command"; exit 1; }
command -v jq >/dev/null || { echo "Missing jq command"; exit 1; }
command -v python3 >/dev/null || { echo "Missing python3 command"; exit 1; }

if [[ -z "$NAME" ]]; then
  NAME="${NAME_PREFIX}-$(date +%Y%m%d-%H%M%S)"
fi

get_bridge_cidr() {
  lxc project switch default >/dev/null
  lxc network show "$BRIDGE" | awk '/ipv4.address:/ {print $2}'
}

pick_free_ip() {
  local cidr="$1"

  lxc project switch default >/dev/null
  local leases_json
  leases_json="$(lxc network list-leases "$BRIDGE" --format json 2>/dev/null || echo '[]')"

  lxc project switch "$PROJECT" >/dev/null
  local instances_json
  instances_json="$(lxc list --format json)"

  python3 - "$cidr" "$leases_json" "$instances_json" <<'PY'
import ipaddress
import json
import sys

cidr = sys.argv[1]
leases = json.loads(sys.argv[2])
instances = json.loads(sys.argv[3])

net = ipaddress.ip_network(cidr, strict=False)
gateway = ipaddress.ip_interface(cidr).ip

used = {gateway}

for lease in leases:
    addr = lease.get("address")
    if addr:
        try:
            used.add(ipaddress.ip_address(addr))
        except ValueError:
            pass

for inst in instances:
    for dev in inst.get("expanded_devices", {}).values():
        addr = dev.get("ipv4.address")
        if addr:
            try:
                used.add(ipaddress.ip_address(addr))
            except ValueError:
                pass

for ip in net.hosts():
    if ip in used:
        continue

    # avoid low/reserved-looking addresses
    if ip.version == 4 and int(str(ip).split(".")[-1]) < 10:
        continue

    print(ip)
    sys.exit(0)

print("No free IP found", file=sys.stderr)
sys.exit(1)
PY
}

update_hosts() {
  local ip="$1"
  local host="$2"

  [[ "$UPDATE_HOSTS" == "1" ]] || return 0
  [[ -n "$ip" ]] || return 0

  if grep -Eq "[[:space:]]${host}([[:space:]]|\$)" "$HOSTS_FILE"; then
    sudo sed -i.bak -E "s|^[0-9a-fA-F:.]+[[:space:]]+${host}([[:space:]].*)?\$|${ip} ${host}|" "$HOSTS_FILE"
  else
    echo "${ip} ${host}" | sudo tee -a "$HOSTS_FILE" >/dev/null
  fi
}

STATIC_IP=""

if [[ "$STATIC_RANDOM_IP" == "1" ]]; then
  BRIDGE_CIDR="$(get_bridge_cidr)"
  STATIC_IP="$(pick_free_ip "$BRIDGE_CIDR")"
fi

lxc project switch "$PROJECT" >/dev/null

lxc launch "$IMAGE" "$NAME" --vm -p "$PROFILE" \
  -c limits.cpu="$CPUS" \
  -c limits.memory="$MEMORY" \
  -d root,size="$DISK"

if [[ -n "$STATIC_IP" ]]; then
  lxc config device override "$NAME" eth0 ipv4.address="$STATIC_IP"
fi

i=0
for mount in "${MOUNTS[@]}"; do
  readonly="false"

  if [[ "$mount" == *":ro" ]]; then
    readonly="true"
    mount="${mount%:ro}"
  fi

  host_path="${mount%%:*}"
  vm_path="${mount#*:}"

  if [[ "$host_path" == "$vm_path" ]]; then
    echo "Invalid mount: $mount"
    echo "Expected format: /host/path:/vm/path[:ro]"
    exit 1
  fi

  if [[ ! -e "$host_path" ]]; then
    echo "Host path does not exist: $host_path"
    exit 1
  fi

  lxc config device add "$NAME" "hostmount${i}" disk \
    source="$host_path" \
    path="$vm_path" \
    readonly="$readonly"

  i=$((i + 1))
done

echo "Waiting for VM..."
until lxc exec "$NAME" -- true 2>/dev/null; do
  sleep 2
done

echo "Created VM: $NAME"

if [[ -n "$STATIC_IP" ]]; then
  update_hosts "$STATIC_IP" "$NAME"
  echo "Static IP: $STATIC_IP"
  echo "Hosts entry: $STATIC_IP $NAME"
fi

echo
echo "Enter with:"
echo "  lxc exec $NAME -- bash"
echo
echo "SSH with:"
if [[ -n "$STATIC_IP" ]]; then
  echo "  ssh ${SSH_USER}@$NAME"
else
  echo "  lxc list $NAME"
fi
echo
echo "Stop/delete with:"
echo "  lxc stop $NAME"
echo "  lxc delete $NAME --force"
