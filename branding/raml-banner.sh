#!/usr/bin/env bash
# raml.ch login banner
# Brand ASCII on the left, live host + network facts on the right.
# Everything is read at display time, so it is always current — including
# right after he has just changed the machine's address.
#
# Install (all users):   sudo cp raml-banner.sh /etc/profile.d/00-raml-banner.sh
# It then runs on every interactive login shell.

# only draw for interactive shells on a real terminal. RAML_BANNER_FORCE=1 is
# set by the zsh path below, which re-runs this file with a non-interactive bash.
case "${RAML_BANNER_FORCE:-}$-" in 1*|*i*) ;; *) return 2>/dev/null || exit 0 ;; esac
[ -t 1 ] || { return 2>/dev/null || exit 0; }

# This script is bash (arrays, read -d ''). Kali's default shell is zsh, so when
# sourced from .zshrc, run it through bash instead of letting zsh parse it.
if [ -n "${ZSH_VERSION:-}" ]; then
  _RAML_BANNER_SRC="${(%):-%x}"
  _raml_banner() {
    RAML_BANNER_FORCE=1 COLUMNS="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}" \
      bash "$_RAML_BANNER_SRC"
  }
  clear() { _raml_banner; }
  _raml_banner
  return 0
fi

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
# ponytail: read loop instead of mapfile — bash 3.2 (macOS) has no mapfile.
logo_lines=(); while IFS= read -r _l; do logo_lines+=("$_l"); done <<< "$LOGO"
LOGO_WIDTH=54
MIN_GAP=3     # minimum space between logo and info when terminal is narrow
PAD=4         # inset from the left and right terminal edges
INDENT=$(printf '%*s' "$PAD" '')

# terminal width. COLUMNS is usually unset in a non-interactive profile.d
# context, so ask the tty itself via stty; fall back to tput, then 80.
COLS=${COLUMNS:-0}; ROWS=${LINES:-0}
_size=$(stty size 2>/dev/null </dev/tty)         # "rows cols"
[ "${ROWS:-0}" -gt 0 ] 2>/dev/null || ROWS=${_size% *}
[ "${COLS:-0}" -gt 0 ] 2>/dev/null || COLS=${_size#* }
[ "${COLS:-0}" -gt 0 ] 2>/dev/null || COLS=$(tput cols 2>/dev/null)
[ "${ROWS:-0}" -gt 0 ] 2>/dev/null || ROWS=$(tput lines 2>/dev/null)
[ "${COLS:-0}" -gt 0 ] 2>/dev/null || COLS=80
[ "${ROWS:-0}" -gt 0 ] 2>/dev/null || ROWS=24

# visible width of a string = length after stripping ANSI escape sequences
vlen() { local s=${1//$'\033'\[*([0-9;])m/}; printf '%s' "${#s}"; }

command clear 2>/dev/null || printf '\033[H\033[2J\033[3J'   # wipe login noise + scrollback
shopt -s extglob   # needed for the *([0-9;]) pattern in vlen

# widest info line → the whole block is left-aligned to this column, then
# that column is pushed to the right edge. Keeps labels in one clean column.
block_w=0
for line in "${info[@]}"; do w=$(vlen "$line"); (( w > block_w )) && block_w=$w; done
block_col=$(( COLS - PAD - block_w ))           # x where the block starts (right inset)
(( block_col < PAD + LOGO_WIDTH + MIN_GAP )) && block_col=$(( PAD + LOGO_WIDTH + MIN_GAP ))

# vertically center the logo against the (taller) info block
n_logo=${#logo_lines[@]}; n_info=${#info[@]}
total=$(( n_logo > n_info ? n_logo : n_info ))
logo_off=$(( (total - n_logo) / 2 ))            # push shorter side down to center it
info_off=$(( (total - n_info) / 2 ))

printf "\n"
for ((i=0; i<total; i++)); do
    li=$(( i - logo_off )); ii=$(( i - info_off ))
    drew_logo=0
    if (( li >= 0 && li < n_logo )); then
        printf "%s${RED}%s${RESET}" "$INDENT" "${logo_lines[li]}"; drew_logo=1
    fi
    if (( ii >= 0 && ii < n_info )); then
        left_w=$(( drew_logo ? PAD + LOGO_WIDTH : 0 ))
        printf '%*s%b' "$(( block_col - left_w ))" '' "${info[ii]}"
    fi
    printf "\n"
done
echo
}

# override `clear` so it redraws the banner instead of a blank screen
clear() { command clear 2>/dev/null || printf '\033[H\033[2J\033[3J'; _raml_banner; }

# draw once on login
_raml_banner
