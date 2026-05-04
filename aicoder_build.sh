#!/usr/bin/env bash
set -euo pipefail

PROJECT="${AICODER_PROJECT:-aicoder}"
PROFILE="${AICODER_PROFILE:-aicoder}"
BASE_IMAGE="${AICODER_BASE_IMAGE:-images:debian/trixie/cloud}"
IMAGE_ALIAS="${AICODER_IMAGE_ALIAS:-aicoder-debian-trixie}"
BUILDER_NAME="${AICODER_BUILDER_NAME:-aicoder-builder}"

SSH_USER="${AICODER_SSH_USER:-coder}"
SSH_PUBKEY_FILE="${AICODER_SSH_PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
SSH_PUBKEY=""

INSTALL_OPENCODE="${AICODER_INSTALL_OPENCODE:-1}"
PACKAGES="${AICODER_PACKAGES:-curl ca-certificates wget git vim jq htop tmux screen ripgrep fd-find unzip zip openssh-server sudo build-essential python3 python3-pip python3-venv nodejs npm}"

command -v lxc >/dev/null || { echo "Missing lxc command"; exit 1; }
command -v jq >/dev/null || { echo "Missing jq command"; exit 1; }

exists_instance() {
  lxc list --format json | jq -r '.[].name' | grep -Fxq "$1"
}

exists_image_alias() {
  lxc image alias list --format json | jq -r '.[].name' | grep -Fxq "$1"
}

if [[ -z "$SSH_PUBKEY" && -f "$SSH_PUBKEY_FILE" ]]; then
  SSH_PUBKEY="$(cat "$SSH_PUBKEY_FILE")"
fi

if [[ -z "$SSH_PUBKEY" ]]; then
  echo "Missing SSH public key. Set AICODER_SSH_PUBKEY_FILE."
  exit 1
fi

lxc project switch "$PROJECT"

if exists_instance "$BUILDER_NAME"; then
  lxc delete "$BUILDER_NAME" --force
fi

lxc launch "$BASE_IMAGE" "$BUILDER_NAME" --vm -p "$PROFILE" -v --debug 2>&1

echo "Waiting for cloud-init..."
until lxc exec "$BUILDER_NAME" -- test -f /var/lib/cloud/instance/boot-finished 2>/dev/null; do
  sleep 3
done

lxc exec "$BUILDER_NAME" -- bash -s <<EOF
set -euo pipefail

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ${PACKAGES}

if ! id '${SSH_USER}' >/dev/null 2>&1; then
  useradd -m -s /bin/bash '${SSH_USER}'
  usermod -aG sudo '${SSH_USER}'
  echo '${SSH_USER} ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/90-aicoder-${SSH_USER}
  chmod 0440 /etc/sudoers.d/90-aicoder-${SSH_USER}
fi

install -d -m 700 -o '${SSH_USER}' -g '${SSH_USER}' /home/'${SSH_USER}'/.ssh
cat >/home/'${SSH_USER}'/.ssh/authorized_keys <<'KEYEOF'
${SSH_PUBKEY}
KEYEOF
chown '${SSH_USER}:${SSH_USER}' /home/'${SSH_USER}'/.ssh/authorized_keys
chmod 600 /home/'${SSH_USER}'/.ssh/authorized_keys

mkdir -p /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/90-aicoder.conf <<'SSHEOF'
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AuthorizedKeysFile .ssh/authorized_keys
SSHEOF

systemctl enable ssh

if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
  ln -sf /usr/bin/fdfind /usr/local/bin/fd
fi

cat >/etc/profile.d/aicoder.sh <<'PROFILEEOF'
export TERM=\${TERM:-xterm-256color}
export COLORTERM=\${COLORTERM:-truecolor}
export EDITOR=\${EDITOR:-vim}
PROFILEEOF

if [[ '${INSTALL_OPENCODE}' == '1' ]]; then
  sudo -u $SSH_USER bash -c 'curl -fsSL https://opencode.ai/install | bash'
fi

apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

lxc stop "$BUILDER_NAME"

if exists_image_alias "$IMAGE_ALIAS"; then
  lxc image delete "$IMAGE_ALIAS"
fi

lxc publish "$BUILDER_NAME" --alias "$IMAGE_ALIAS"
lxc delete "$BUILDER_NAME" --force

echo "Built image: $IMAGE_ALIAS"
