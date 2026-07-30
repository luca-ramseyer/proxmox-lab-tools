#!/usr/bin/env bash
#
# add-vms.sh - clone the lab guest VMs into an existing pod
#
# provision-lab.sh builds the pod (bridges, pool, user, firewall). This adds
# the guests on top and pins each one to the right zone bridge.
#
# Usage:  ./add-vms.sh -n 2 -u busd --dry-run
#         ./add-vms.sh -n 2 -u busd
#         ./add-vms.sh -n 2 -u busd --only kali,win11
#
set -euo pipefail

# ---------------------------------------------------------------- config
# Template VMIDs, confirmed against `qm list` on the host.
# Note server/desktop are 9000/9001 respectively — the reverse of what an
# earlier README draft claimed. Re-check with `qm list` if templates get rebuilt.
TPL_UBUNTU_SERVER=9000    # tmpl-ub-srv
TPL_UBUNTU_DESKTOP=9001   # tmpl-ub-de
TPL_WIN11=9002            # tmpl-win-11
TPL_KALI=9003             # tmpl-kl-de

STORAGE=local-lvm         # where full clones land
BRIDGE_WAN=vmbr0          # only used for the note printed at the end

# The lab roster: name:template-var:zone
# zone is lan | dmz | srv and maps to the pod bridge of the same zone.
# VMID is assigned as pod base + offset, in roster order (see VMID_OFFSET).
ROSTER=(
  "ubu-de-01:TPL_UBUNTU_DESKTOP:lan"
  "win11-01:TPL_WIN11:lan"
  "kali-01:TPL_KALI:lan"
  "ubu-srv-dmz:TPL_UBUNTU_SERVER:dmz"
  "ubu-srv-srv:TPL_UBUNTU_SERVER:srv"
)
VMID_OFFSET=10            # first guest gets base+10, then +11, +12 ...

# ---------------------------------------------------------------- args
LAB_NUM=""; LAB_USER=""; DRY_RUN=0; ONLY=""; START=0

usage() {
  cat <<EOF
Usage: $0 -n <lab-number 1-9> -u <username> [--only a,b] [--start] [--dry-run]

  -n        lab number; must match the pod created by provision-lab.sh
  -u        short username; pool is lab-<user>
  --only    comma-separated subset of guest names to create
  --start   power the guests on after creating them (default: leave stopped)
  --dry-run print what would happen, change nothing

Guests created (name -> zone):
$(for e in "${ROSTER[@]}"; do printf '  %-14s %s\n' "${e%%:*}" "${e##*:}"; done)
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) LAB_NUM="$2"; shift 2 ;;
    -u) LAB_USER="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --start) START=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) usage ;;
  esac
done

[[ -z "$LAB_NUM" || -z "$LAB_USER" ]] && usage
[[ "$LAB_NUM" =~ ^[1-9]$ ]] || { echo "lab number must be 1-9"; exit 1; }

# ---------------------------------------------------------------- derived
# Mirrors provision-lab.sh exactly; keep the two in sync.
POOL="lab-${LAB_USER}"
BR_LAN="vmbr${LAB_NUM}1"
BR_DMZ="vmbr${LAB_NUM}2"
BR_SRV="vmbr${LAB_NUM}3"
BASE=$(( LAB_NUM * 1000 ))
FW_VMID=$BASE

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

bridge_for() {
  case "$1" in
    lan) echo "$BR_LAN" ;;
    dmz) echo "$BR_DMZ" ;;
    srv) echo "$BR_SRV" ;;
    *) echo "unknown zone '$1'" >&2; exit 1 ;;
  esac
}

wanted() {
  [[ -z "$ONLY" ]] && return 0
  case ",${ONLY}," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------- preflight
say "Preflight"

[[ $EUID -eq 0 ]] || { echo "must run as root on the Proxmox host"; exit 1; }

# The pod must already exist - this script adds to it, it does not create it.
pvesh get /pools --output-format json 2>/dev/null | grep -q "\"$POOL\"" || {
  echo "pool $POOL not found. Run provision-lab.sh -n $LAB_NUM -u $LAB_USER first."
  exit 1
}

qm status "$FW_VMID" &>/dev/null || {
  echo "firewall $FW_VMID not found. Run provision-lab.sh first."
  exit 1
}

for br in "$BR_LAN" "$BR_DMZ" "$BR_SRV"; do
  ip link show "$br" &>/dev/null || {
    echo "bridge $br is missing. Run provision-lab.sh first."
    exit 1
  }
done

# Validate every template we are actually going to use, before cloning any of
# them - a half-populated pod is more annoying than a clean failure.
missing=0
for entry in "${ROSTER[@]}"; do
  IFS=: read -r name tplvar zone <<<"$entry"
  wanted "$name" || continue
  tpl="${!tplvar}"
  if ! qm status "$tpl" &>/dev/null; then
    echo "  template $tpl ($tplvar, for $name) not found"
    missing=1
  fi
done
(( missing == 0 )) || { echo "fix the template VMIDs at the top of this script"; exit 1; }

echo "  pool ............ $POOL"
echo "  firewall ........ $FW_VMID"
echo "  LAN / DMZ / SRV . $BR_LAN / $BR_DMZ / $BR_SRV"

# Existing VM names, so a re-run is idempotent per guest rather than per slot.
# Without this, re-running clones a second copy of every guest at a fresh VMID.
existing_names=$(qm list 2>/dev/null | awk 'NR>1{print $2}')
have_name() {
  local n
  for n in $existing_names; do [[ "$n" == "$1" ]] && return 0; done
  return 1
}

# Plan the VMIDs first so we can print the whole plan and bail on collisions.
declare -a PLAN=()
declare -a SKIPPED=()
next=$(( BASE + VMID_OFFSET ))
for entry in "${ROSTER[@]}"; do
  IFS=: read -r name tplvar zone <<<"$entry"
  wanted "$name" || continue
  full_name="${name}-lab${LAB_NUM}"
  if have_name "$full_name"; then
    SKIPPED+=("$full_name")
    continue
  fi
  # step over VMIDs already in use, so a partial pod fills its gaps
  while qm status "$next" &>/dev/null; do
    next=$(( next + 1 ))
  done
  (( next < BASE + 1000 )) || { echo "ran out of VMIDs in the pod range"; exit 1; }
  PLAN+=("$next:$name:$tplvar:$zone")
  next=$(( next + 1 ))
done

if (( ${#SKIPPED[@]} )); then
  echo "  already present, skipping: ${SKIPPED[*]}"
fi

if (( ${#PLAN[@]} == 0 )); then
  echo "nothing to do - every requested guest already exists"
  exit 0
fi

say "Plan"
for p in "${PLAN[@]}"; do
  IFS=: read -r vmid name tplvar zone <<<"$p"
  printf '  %-5s %-14s <- template %-5s  %s (%s)\n' \
    "$vmid" "$name" "${!tplvar}" "$(bridge_for "$zone")" "$zone"
done

# ---------------------------------------------------------------- clone
say "Cloning guests"

for p in "${PLAN[@]}"; do
  IFS=: read -r vmid name tplvar zone <<<"$p"
  tpl="${!tplvar}"
  br=$(bridge_for "$zone")
  full_name="${name}-lab${LAB_NUM}"
  echo "  $vmid  $full_name  ($zone -> $br)"

  run qm clone "$tpl" "$vmid" \
    --name "$full_name" --full --storage "$STORAGE" --pool "$POOL"

  # Single NIC, pinned to the zone bridge. Students lack VM.Config.Network,
  # so they cannot move it off this bridge and around the firewall.
  run qm set "$vmid" --net0 "virtio,bridge=${br}"
  run qm set "$vmid" --onboot 0
  run qm set "$vmid" --agent enabled=1

  if (( START )); then
    run qm start "$vmid"
  fi
done

# ---------------------------------------------------------------- done
say "Guests added to lab ${LAB_NUM}"

cat <<EOF

  Pool .............. ${POOL}
  Created ........... ${#PLAN[@]} guest(s)$( (( START )) && echo ", started" || echo ", left stopped")

  Zone addressing (the firewall holds .1 in each):
    LAN   10.${LAB_NUM}.10.0/24   ${BR_LAN}
    DMZ   10.${LAB_NUM}.20.0/24   ${BR_DMZ}
    SRV   10.${LAB_NUM}.30.0/24   ${BR_SRV}   <- unconfigured on the firewall

  The SRV guest has no gateway until the student brings OPT2 up in OPNsense.
  That is the exercise, not a bug.

  Branding is not applied here - run the installers on each guest:
    Linux    curl -fsSL <raw>/branding/install.sh | sudo bash -s -- desktop
    Windows  see branding/install.ps1

EOF
