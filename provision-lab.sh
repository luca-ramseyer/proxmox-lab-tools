#!/usr/bin/env bash
#
# new-lab.sh - provision an isolated lab pod on Proxmox VE
#
# Creates: 3 private bridges, a resource pool, a PVE user, a cloned
# OPNsense firewall wired into all three zones, and the ACLs that
# scope the user to their own pod.
#
# Usage:  ./new-lab.sh -n 2 -u busd
#         ./new-lab.sh -n 3 -u tom -p 'somepassword' --dry-run
#
set -euo pipefail

# ---------------------------------------------------------------- config
FW_TEMPLATE=9100          # VMID of the golden OPNsense template
WAN_BRIDGE=vmbr0          # shared uplink to the real network
STORAGE=local-lvm         # where full clones land
LAB_ROLE=LabUser          # custom role granted on the pod's pool
IFACES=/etc/network/interfaces
BASE_DOMAIN=lab.raml.ch   # per-lab domain becomes <user>.<BASE_DOMAIN>
FW_HOSTNAME=fw-01         # same in every pod; the domain disambiguates
AGENT_TIMEOUT=180         # seconds to wait for the guest agent after boot

# ---------------------------------------------------------------- args
LAB_NUM=""; LAB_USER=""; LAB_PASS=""; DRY_RUN=0

usage() {
  cat <<EOF
Usage: $0 -n <lab-number 1-9> -u <username> [-p <password>] [--dry-run]

  -n   lab number; drives bridge names, subnets and VMIDs
  -u   short username, e.g. 'busd' -> pool lab-busd, user busd@pve
  -p   password for the new PVE user (prompted if omitted)
       pass -p '' to skip user creation entirely
  --dry-run   print what would happen, change nothing
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) LAB_NUM="$2"; shift 2 ;;
    -u) LAB_USER="$2"; shift 2 ;;
    -p) LAB_PASS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) usage ;;
  esac
done

[[ -z "$LAB_NUM" || -z "$LAB_USER" ]] && usage
[[ "$LAB_NUM" =~ ^[1-9]$ ]] || { echo "lab number must be 1-9"; exit 1; }

# ---------------------------------------------------------------- derived
POOL="lab-${LAB_USER}"
BR_LAN="vmbr${LAB_NUM}1"
BR_DMZ="vmbr${LAB_NUM}2"
BR_SRV="vmbr${LAB_NUM}3"
FW_VMID=$(( LAB_NUM * 1000 ))
FW_NAME="fw-lab${LAB_NUM}"
NET_LAN="10.${LAB_NUM}.10.0/24"
NET_DMZ="10.${LAB_NUM}.20.0/24"
NET_SRV="10.${LAB_NUM}.30.0/24"
LAB_DOMAIN="${LAB_USER}.${BASE_DOMAIN}"

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- preflight
say "Preflight"

[[ $EUID -eq 0 ]] || { echo "must run as root on the Proxmox host"; exit 1; }

qm status "$FW_TEMPLATE" &>/dev/null || {
  echo "firewall template $FW_TEMPLATE not found."
  echo "Build an OPNsense golden image and 'qm template' it first."
  exit 1
}

if qm status "$FW_VMID" &>/dev/null; then
  echo "VMID $FW_VMID already exists - lab $LAB_NUM looks provisioned."
  exit 1
fi

echo "  lab number ...... $LAB_NUM"
echo "  pool ............ $POOL"
echo "  firewall ........ $FW_VMID ($FW_NAME)"
echo "  LAN ............. $BR_LAN  $NET_LAN"
echo "  DMZ ............. $BR_DMZ  $NET_DMZ"
echo "  SRV ............. $BR_SRV  $NET_SRV   (left unconfigured on purpose)"

# ---------------------------------------------------------------- bridges
say "Creating bridges"

add_bridge() {
  local br="$1" comment="$2"
  if grep -qE "^iface ${br} " "$IFACES"; then
    echo "  $br already present, skipping"
    return
  fi
  echo "  $br  ($comment)"
  if [[ $DRY_RUN -eq 0 ]]; then
    cat >>"$IFACES" <<EOF

auto ${br}
iface ${br} inet manual
	bridge-ports none
	bridge-stp off
	bridge-fd 0
#${comment}
EOF
  fi
}

if [[ $DRY_RUN -eq 0 ]]; then
  cp "$IFACES" "${IFACES}.bak.$(date +%s)"
fi

add_bridge "$BR_LAN" "lab${LAB_NUM} LAN"
add_bridge "$BR_DMZ" "lab${LAB_NUM} DMZ"
add_bridge "$BR_SRV" "lab${LAB_NUM} SRV"

run ifreload -a

# ---------------------------------------------------------------- pool
say "Creating pool"

if pvesh get /pools --output-format json 2>/dev/null | grep -q "\"$POOL\""; then
  echo "  pool $POOL already exists"
else
  run pveum pool add "$POOL" --comment "Lab ${LAB_NUM} - ${LAB_USER}"
fi

# ---------------------------------------------------------------- firewall
say "Cloning firewall"

run qm clone "$FW_TEMPLATE" "$FW_VMID" \
  --name "$FW_NAME" --full --storage "$STORAGE" --pool "$POOL"

run qm set "$FW_VMID" \
  --net0 "virtio,bridge=${WAN_BRIDGE}" \
  --net1 "virtio,bridge=${BR_LAN}" \
  --net2 "virtio,bridge=${BR_DMZ}" \
  --net3 "virtio,bridge=${BR_SRV}"

run qm set "$FW_VMID" --onboot 1
run qm set "$FW_VMID" --agent enabled=1

# ---------------------------------------------------------------- identity
say "Setting firewall identity"

echo "  hostname ........ ${FW_HOSTNAME}"
echo "  domain .......... ${LAB_DOMAIN}"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "  [dry-run] would boot ${FW_VMID}, wait for guest agent, patch config.xml"
else
  qm start "$FW_VMID"

  printf '  waiting for guest agent '
  waited=0
  until qm agent "$FW_VMID" ping &>/dev/null; do
    if (( waited >= AGENT_TIMEOUT )); then
      echo
      echo "  guest agent did not respond within ${AGENT_TIMEOUT}s."
      echo "  Set hostname/domain manually in the OPNsense GUI:"
      echo "    System > Settings > General"
      exit 1
    fi
    printf '.'
    sleep 5
    waited=$(( waited + 5 ))
  done
  echo " ok"

  # OPNsense keeps both values in /conf/config.xml under <system>.
  # FreeBSD sed needs an explicit backup suffix for -i, hence -i ''.
  qm guest exec "$FW_VMID" -- /bin/sh -c "
    cp /conf/config.xml /conf/config.xml.preprovision &&
    sed -i '' 's|<hostname>.*</hostname>|<hostname>${FW_HOSTNAME}</hostname>|' /conf/config.xml &&
    sed -i '' 's|<domain>.*</domain>|<domain>${LAB_DOMAIN}</domain>|' /conf/config.xml
  " >/dev/null

  echo "  applying (firewall will reboot)"
  qm guest exec "$FW_VMID" -- /sbin/reboot >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------- user
say "User and permissions"

if [[ "${LAB_PASS-unset}" == "unset" ]]; then
  read -rsp "  password for ${LAB_USER}@pve (empty to skip user): " LAB_PASS
  echo
fi

if [[ -z "$LAB_PASS" ]]; then
  echo "  skipping user creation"
else
  if pveum user list --output-format json | grep -q "\"${LAB_USER}@pve\""; then
    echo "  user ${LAB_USER}@pve already exists"
  else
    run pveum user add "${LAB_USER}@pve" --password "$LAB_PASS" \
      --comment "Lab ${LAB_NUM}"
  fi
  run pveum aclmod "/pool/${POOL}" \
    --users "${LAB_USER}@pve" --roles "$LAB_ROLE" --propagate 1
fi

# ---------------------------------------------------------------- done
say "Lab ${LAB_NUM} ready"

cat <<EOF

  Firewall VM ....... ${FW_VMID} (${FW_NAME}), booting
  FQDN .............. ${FW_HOSTNAME}.${LAB_DOMAIN}
  Bridges ........... ${BR_LAN} / ${BR_DMZ} / ${BR_SRV}
  Pool .............. ${POOL}

  Planned addressing (configure inside OPNsense):
    WAN   DHCP from ${WAN_BRIDGE}
    LAN   10.${LAB_NUM}.10.1/24    vtnet1
    DMZ   10.${LAB_NUM}.20.1/24    vtnet2
    SRV   10.${LAB_NUM}.30.1/24    vtnet3   <- left for the student

  Next:
    attach a VM to ${BR_LAN} and browse to https://10.${LAB_NUM}.10.1
    (rolled back config saved as /conf/config.xml.preprovision)

  Lab VMs for this pod should use VMIDs ${FW_VMID}..$(( FW_VMID + 999 )).

EOF