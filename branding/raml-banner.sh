#!/usr/bin/env bash
# raml.ch login banner
# Brand ASCII on the left, live host + network facts on the right.
# Everything is read at display time, so it is always current — including
# right after he has just changed the machine's address.
#
# Install (all users):   sudo cp raml-banner.sh /etc/profile.d/00-raml-banner.sh
# It then runs on every interactive login shell.

# only draw for interactive shells on a real terminal
case $- in *i*) ;; *) return 2>/dev/null || exit 0 ;; esac
[ -t 1 ] || { return 2>/dev/null || exit 0; }

# ── brand colours (truecolor) ───────────────────────────────────────────
RED=$'\033[38;2;192;71;58m'      # Swiss Red  #C0473A
INK=$'\033[38;2;173;168;158m'    # muted label
CREAM=$'\033[38;2;244;239;228m'  # value text
DIM=$'\033[38;2;120;116;108m'
BOLD=$'\033[1m'; RESET=$'\033[0m'

read -r -d '' LOGO << 'LOGO_EOF'
██████╗  █████╗ ███╗   ███╗██╗         ██████╗██╗  ██╗
██╔══██╗██╔══██╗████╗ ████║██║        ██╔════╝██║  ██║
██████╔╝███████║██╔████╔██║██║        ██║     ███████║
██╔══██╗██╔══██║██║╚██╔╝██║██║        ██║     ██╔══██║
██║  ██║██║  ██║██║ ╚═╝ ██║███████╗██╗╚██████╗██║  ██║
╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚═╝ ╚═════╝╚═╝  ╚═╝
LOGO_EOF

_raml_banner() {
# ── live facts (re-read every call, so `clear` shows current state) ───────
HOSTNAME_F=$(hostname)
FQDN_F=$(hostname -f 2>/dev/null || echo "$HOSTNAME_F")
OS_F=$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-$(uname -s)}")
KERNEL_F=$(uname -r)
UPTIME_F=$(uptime -p 2>/dev/null | sed 's/^up //' || echo "n/a")

PRIMARY_IF=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
GATEWAY_F=$(ip route show default 2>/dev/null | awk '{print $3; exit}')
if [ -n "$PRIMARY_IF" ]; then
    IP_CIDR=$(ip -4 addr show "$PRIMARY_IF" 2>/dev/null | awk '/inet /{print $2; exit}')
    MAC_F=$(cat /sys/class/net/"$PRIMARY_IF"/address 2>/dev/null)
fi
[ -z "$IP_CIDR" ] && IP_CIDR="unconfigured"

DNS_F=$(awk '/^nameserver/{printf "%s ", $2}' /etc/resolv.conf 2>/dev/null | sed 's/ $//')
[ -z "$DNS_F" ] && DNS_F=$(resolvectl dns 2>/dev/null | awk 'NF>1{print $2; exit}')
[ -z "$DNS_F" ] && DNS_F="none"

# ── right-hand info block ────────────────────────────────────────────────
info=()
info+=("${RED}${BOLD}◆${RESET}  ${CREAM}${BOLD}${FQDN_F}${RESET}")
info+=("")
info+=("${INK}host    ${RESET}${CREAM}${HOSTNAME_F}${RESET}")
info+=("${INK}os      ${RESET}${CREAM}${OS_F}${RESET}")
info+=("${INK}kernel  ${RESET}${CREAM}${KERNEL_F}${RESET}")
info+=("${INK}uptime  ${RESET}${CREAM}${UPTIME_F}${RESET}")
info+=("")
info+=("${INK}iface   ${RESET}${CREAM}${PRIMARY_IF:-none}${RESET}")
info+=("${INK}addr    ${RESET}${RED}${BOLD}${IP_CIDR}${RESET}")
info+=("${INK}gateway ${RESET}${CREAM}${GATEWAY_F:-none}${RESET}")
info+=("${INK}dns     ${RESET}${CREAM}${DNS_F}${RESET}")
info+=("${INK}mac     ${RESET}${DIM}${MAC_F:-n/a}${RESET}")

# ── print: logo left, info flush against the right terminal edge ─────────
mapfile -t logo_lines <<< "$LOGO"
LOGO_WIDTH=54
MIN_GAP=3     # minimum space between logo and info when terminal is narrow

# terminal width, with fallbacks for when COLUMNS/tput are unavailable
COLS=${COLUMNS:-0}
[ "$COLS" -gt 0 ] 2>/dev/null || COLS=$(tput cols 2>/dev/null || echo 80)

# visible width of a string = length after stripping ANSI escape sequences
vlen() { local s=${1//$'\033'\[*([0-9;])m/}; printf '%s' "${#s}"; }

command clear 2>/dev/null || printf '\033[H\033[2J\033[3J'   # wipe login noise + scrollback
echo
shopt -s extglob   # needed for the *([0-9;]) pattern in vlen

# widest info line → the whole block is left-aligned to this column, then
# that column is pushed to the right edge. Keeps labels in one clean column.
block_w=0
for line in "${info[@]}"; do w=$(vlen "$line"); (( w > block_w )) && block_w=$w; done
block_col=$(( COLS - block_w ))                 # x where the block starts
(( block_col < LOGO_WIDTH + MIN_GAP )) && block_col=$(( LOGO_WIDTH + MIN_GAP ))

total=$(( ${#logo_lines[@]} > ${#info[@]} ? ${#logo_lines[@]} : ${#info[@]} ))
for ((i=0; i<total; i++)); do
    (( i < ${#logo_lines[@]} )) && printf "${RED}%s${RESET}" "${logo_lines[i]}"
    if (( i < ${#info[@]} )); then
        left_w=$(( i < ${#logo_lines[@]} ? LOGO_WIDTH : 0 ))
        printf '%*s%b' "$(( block_col - left_w ))" '' "${info[i]}"
    fi
    printf "\n"
done
echo
}

# override `clear` so it redraws the banner instead of a blank screen
clear() { command clear 2>/dev/null || printf '\033[H\033[2J\033[3J'; _raml_banner; }

# draw once on login
_raml_banner
