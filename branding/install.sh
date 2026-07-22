#!/usr/bin/env bash
# raml.ch branding installer — pulls only the files a machine needs.
#
#   Server (headless):   curl -fsSL <raw>/branding/install.sh | sudo bash
#   Desktop (Conky):     curl -fsSL <raw>/branding/install.sh | bash -s -- desktop
#
# Auto-detects: if a graphical session is present, installs the desktop overlay
# too. Force with an arg: `server` or `desktop`.
set -euo pipefail

RAW="https://raw.githubusercontent.com/luca-ramseyer/proxmox-lab-tools/main/branding"

# ── pick profile ─────────────────────────────────────────────────────────
mode="${1:-auto}"
if [ "$mode" = auto ]; then
  # a desktop session sets XDG_CURRENT_DESKTOP or has an X/Wayland display
  if [ -n "${XDG_CURRENT_DESKTOP:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; then
    mode=desktop
  else
    mode=server
  fi
fi
echo "raml branding: installing '$mode' profile"

fetch() { curl -fsSL "$RAW/$1" -o "$2"; }

# ── terminal banner — every profile gets it ──────────────────────────────
# needs root for /etc/profile.d; re-exec under sudo if not already root.
if [ "$(id -u)" -eq 0 ]; then
  fetch raml-banner.sh /etc/profile.d/00-raml-banner.sh
  chmod 0644 /etc/profile.d/00-raml-banner.sh
  echo "  ✓ terminal banner -> /etc/profile.d/00-raml-banner.sh"
else
  # ponytail: single-user fallback, no sudo. Sources from ~/.bashrc instead.
  mkdir -p "$HOME/.local/share/raml"
  fetch raml-banner.sh "$HOME/.local/share/raml/raml-banner.sh"
  grep -q 'raml-banner.sh' "$HOME/.bashrc" 2>/dev/null || \
    echo '. "$HOME/.local/share/raml/raml-banner.sh"' >> "$HOME/.bashrc"
  echo "  ✓ terminal banner -> ~/.local/share/raml (sourced from .bashrc)"
fi

# ── desktop overlay — Conky ──────────────────────────────────────────────
if [ "$mode" = desktop ]; then
  command -v conky >/dev/null || echo "  ! conky not installed — 'sudo apt install conky' then re-run"
  mkdir -p "$HOME/.config/conky" "$HOME/.config/autostart"
  fetch conky-raml.conf   "$HOME/.config/conky/conky.conf"      # .desktop expects this name
  fetch raml-conky.desktop "$HOME/.config/autostart/raml-conky.desktop"
  echo "  ✓ conky overlay -> ~/.config/conky + autostart"
fi

echo "done. terminal banner shows on next login."
