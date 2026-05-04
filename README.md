# AICoder LXD VM Environment

Helper scripts for creating fresh, disposable LXD VM environments for Codex/OpenCode-style development.

The scripts provide:

- dedicated LXD project
- dedicated LXD bridge network
- reusable Debian Trixie VM image
- preinstalled custom software
- OpenCode TUI support
- SSH public-key login
- fresh VM creation
- optional multiple host mounts
- optional read-only mounts
- static IP assignment from the bridge subnet
- `/etc/hosts` update for SSH by VM name

---

## Files

```text
aicoder_setup.sh    # prepares LXD project, bridge, and profile
aicoder_build.sh    # builds the reusable base VM image
aicoder_new.sh      # creates a fresh VM instance
.env.example        # all configurable environment variables
README.md           # this file
```

---

## Requirements

Host packages/tools:

```text
lxc
jq
python3
sudo
```

LXD must already be initialized.

Check:

```bash
lxc storage list
```

---

## Configuration

1. Copy the example environment file:

```bash
cp .env.example .env
```

2. Edit it:

```bash
vim .env
```

3. Load it before running scripts:

```bash
source .env
```

All configuration is controlled through environment variables from `.env`.

---

## RUN

### Initial Setup

Run once:

```bash
./aicoder_setup.sh
```

This creates or updates:

- LXD project
- bridge network
- LXD profile

The bridge is created as a normal Linux bridge, not OVN.

---

### Build the Base Image

```bash
./aicoder_build.sh
```

This script:

1. launches a temporary builder VM
2. waits for cloud-init
3. installs configured packages
4. installs and enables SSH
5. adds your SSH public key
6. disables password SSH login
7. optionally installs OpenCode
8. publishes the VM as an LXD image
9. deletes the builder VM

Default image alias:

```text
aicoder-debian-trixie
```

---

### Create a New VM


```bash
./aicoder_new.sh -n codex-test
```

Without `-n`, the script generates a name automatically:

```text
aicoder-YYYYMMDD-HHMMSS
```

---

## Profit

Inside a VM:

```bash
cd /workspace
opencode
```
