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

# ── live facts ───────────────────────────────────────────────────────────
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

# ── print side by side, top-aligned, overflow below the logo ─────────────
mapfile -t logo_lines <<< "$LOGO"
GAP="   "
LOGO_WIDTH=54
BLANK=$(printf '%*s' "$LOGO_WIDTH" '')

clear 2>/dev/null || printf '\033[H\033[2J\033[3J'   # wipe login noise (incl. scrollback)
echo
total=$(( ${#logo_lines[@]} > ${#info[@]} ? ${#logo_lines[@]} : ${#info[@]} ))
for ((i=0; i<total; i++)); do
    if (( i < ${#logo_lines[@]} )); then
        printf "${RED}%s${RESET}%s" "${logo_lines[i]}" "$GAP"
    else
        printf "%s%s" "$BLANK" "$GAP"
    fi
    (( i < ${#info[@]} )) && printf "%b" "${info[i]}"
    printf "\n"
done
echo
