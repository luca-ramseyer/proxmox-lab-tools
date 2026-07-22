#!/usr/bin/env bash
# raml.ch branding installer — pulls only the files a machine needs.
#
#   Server (headless):   curl -fsSL <raw>/branding/install.sh | sudo bash
#   Desktop (full):      curl -fsSL <raw>/branding/install.sh | sudo bash -s -- desktop
#                        (installs banner + Conky + wallpaper)
#
# One command does everything: run it with sudo. Per-user files (banner,
# Conky, wallpaper) go to the real login user's home even under sudo; the
# system bits (profile.d banner, MOTD) use root. Auto-detects server vs
# desktop; force with `server` or `desktop`.
set -euo pipefail

RAW="https://raw.githubusercontent.com/luca-ramseyer/proxmox-lab-tools/main/branding"

# Wallpaper: public raw URL to the image. Override at runtime with WALL_URL=...
WALL_URL="${WALL_URL:-https://raw.githubusercontent.com/luca-ramseyer/brand/main/assets/wallpapers/raml-swiss-mac-mono-dark.png}"

fetch() { curl -fsSL "$1" -o "$2"; }

# ── resolve the real (non-root) user, even under sudo ────────────────────
TARGET_USER="${SUDO_USER:-$USER}"
[ "$TARGET_USER" = root ] && TARGET_USER="$(logname 2>/dev/null || echo root)"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)"
[ -n "$TARGET_HOME" ] || TARGET_HOME="$HOME"
IS_ROOT=0; [ "$(id -u)" -eq 0 ] && IS_ROOT=1

# run a command as the target user (keeps files owned by them, not root)
as_user() {
  if [ "$IS_ROOT" -eq 1 ] && [ "$TARGET_USER" != root ]; then
    sudo -u "$TARGET_USER" "$@"
  else
    "$@"
  fi
}

# ── pick profile ─────────────────────────────────────────────────────────
mode="${1:-auto}"
if [ "$mode" = auto ]; then
  # a desktop session sets XDG_CURRENT_DESKTOP or has an X/Wayland display.
  # under sudo these are often empty, so also treat "GUI user home has a
  # gnome session bus" as desktop — but keep it simple: a real seat = desktop.
  if [ -n "${XDG_CURRENT_DESKTOP:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ] \
     || loginctl show-user "$TARGET_USER" 2>/dev/null | grep -q 'Display='; then
    mode=desktop
  else
    mode=server
  fi
fi
echo "raml branding: installing '$mode' profile for user '$TARGET_USER'"

# ── terminal banner ──────────────────────────────────────────────────────
if [ "$IS_ROOT" -eq 1 ]; then
  fetch "$RAW/raml-banner.sh" /etc/profile.d/00-raml-banner.sh
  chmod 0644 /etc/profile.d/00-raml-banner.sh
  echo "  ✓ terminal banner -> /etc/profile.d/00-raml-banner.sh"
  # profile.d only fires for LOGIN shells; GNOME Terminal opens non-login
  # interactive shells, so also source it from the user's ~/.bashrc.
  if [ "$TARGET_USER" != root ] && [ -n "$TARGET_HOME" ]; then
    line='[ -r /etc/profile.d/00-raml-banner.sh ] && . /etc/profile.d/00-raml-banner.sh'
    grep -qF '00-raml-banner.sh' "$TARGET_HOME/.bashrc" 2>/dev/null || \
      as_user bash -c "printf '%s\n' '$line' >> '$TARGET_HOME/.bashrc'"
    echo "  ✓ banner also sourced from ~/.bashrc (non-login shells)"
  fi
else
  # ponytail: no-sudo fallback. Sources from ~/.bashrc instead.
  mkdir -p "$TARGET_HOME/.local/share/raml"
  fetch "$RAW/raml-banner.sh" "$TARGET_HOME/.local/share/raml/raml-banner.sh"
  grep -q 'raml-banner.sh' "$TARGET_HOME/.bashrc" 2>/dev/null || \
    echo '. "$HOME/.local/share/raml/raml-banner.sh"' >> "$TARGET_HOME/.bashrc"
  echo "  ✓ terminal banner -> ~/.local/share/raml (sourced from .bashrc)"
fi

# ── disable Ubuntu MOTD — replaced by raml banner ────────────────────────
# ponytail: chmod -x, not deleting the scripts. Reversible; apt won't restore.
if [ "$IS_ROOT" -eq 1 ] && [ -d /etc/update-motd.d ]; then
  chmod -x /etc/update-motd.d/* 2>/dev/null || true
  [ -f /etc/motd ] && : > /etc/motd
  echo "  ✓ Ubuntu MOTD disabled"
fi

# ── desktop-only: Conky overlay + wallpaper ──────────────────────────────
if [ "$mode" = desktop ]; then
  command -v conky >/dev/null || echo "  ! conky not installed — 'sudo apt install -y conky-all' then re-run"

  cfg="$TARGET_HOME/.config"
  as_user mkdir -p "$cfg/conky" "$cfg/autostart" "$TARGET_HOME/.local/share/raml"
  as_user bash -c "curl -fsSL '$RAW/conky-raml.conf'    -o '$cfg/conky/conky.conf'"
  as_user bash -c "curl -fsSL '$RAW/raml-conky.desktop' -o '$cfg/autostart/raml-conky.desktop'"
  echo "  ✓ conky overlay -> ~/.config/conky + autostart"

  # wallpaper (GNOME). Needs the image URL and the user's session dbus.
  if [ -n "$WALL_URL" ]; then
    wall="$TARGET_HOME/.local/share/raml/wallpaper"
    if as_user bash -c "curl -fsSL '$WALL_URL' -o '$wall'"; then
      uid="$(id -u "$TARGET_USER")"
      # gsettings needs DBUS_SESSION_BUS_ADDRESS to reach the running GNOME.
      set_wall() {
        as_user env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
          gsettings set "$1" "$2" "$3" 2>/dev/null
      }
      set_wall org.gnome.desktop.background picture-uri       "file://$wall" || true
      set_wall org.gnome.desktop.background picture-uri-dark  "file://$wall" || true
      set_wall org.gnome.desktop.background picture-options   "zoom"         || true
      echo "  ✓ wallpaper set (re-login if it doesn't apply immediately)"
    else
      echo "  ! wallpaper download failed from \$WALL_URL — skipped"
    fi
  else
    echo "  · wallpaper skipped — set WALL_URL to your brand repo's raw image URL"
  fi
fi

echo "done. terminal banner shows on next login."
