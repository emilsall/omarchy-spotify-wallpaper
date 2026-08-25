#!/bin/bash
# install.sh — Set up the Spotify Album Wallpaper plugin's background service.
#
# Run once after `omarchy plugin add`. Installs missing Arch packages (when
# invoked with --install-deps, through a polkit password prompt), a systemd
# user service that watches Spotify playback, and a theme-set hook that keeps
# the restorable wallpaper reference current.
#
# Exit codes:
#   0  service installed (or already present and refreshed)
#   2  dependencies missing and --install-deps was not given
#   1  dependency installation canceled/failed, or other setup failure
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="$(basename "$PLUGIN_DIR")"
SERVICE_NAME="omarchy-spotify-wallpaper.service"
SERVICE_DIR="$HOME/.config/systemd/user"

INSTALL_DEPS=false
for arg in "$@"; do
  case "$arg" in
    --install-deps) INSTALL_DEPS=true ;;
    --help) echo "Usage: install.sh [--install-deps]"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

echo "Installing Spotify Album Wallpaper ($PLUGIN_ID)"

# Ordered dependency list: command, Arch package.
DEP_CMDS=(playerctl jq magick curl)
DEP_PKGS=(playerctl jq imagemagick curl)

missing_cmds=()
missing_pkgs=()
check_deps() {
  missing_cmds=()
  missing_pkgs=()
  for i in "${!DEP_CMDS[@]}"; do
    local cmd="${DEP_CMDS[$i]}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing_cmds+=("$cmd")
      missing_pkgs+=("${DEP_PKGS[$i]}")
    fi
  done
}

check_deps

if (( ${#missing_cmds[@]} > 0 )); then
  if [[ "$INSTALL_DEPS" == "false" ]]; then
    # Single clean line the panel can display.
    echo "Missing dependencies: ${missing_cmds[*]}" >&2
    exit 2
  fi

  echo "Requesting authorization to install: ${missing_pkgs[*]}"
  # pkexec triggers Omarchy's polkit agent (graphical password prompt).
  if ! pkexec omarchy pkg add "${missing_pkgs[@]}"; then
    echo "Dependency installation was canceled or failed." >&2
    exit 1
  fi

  check_deps
  if (( ${#missing_cmds[@]} > 0 )); then
    echo "Dependencies still missing after install: ${missing_cmds[*]}" >&2
    exit 1
  fi
  echo "Dependencies installed."
fi

# Install systemd user service
mkdir -p "$SERVICE_DIR"
sed "s|%h/.config/omarchy/plugins/emilsall.spotify-wallpaper|%h/.config/omarchy/plugins/$PLUGIN_ID|" \
  "$PLUGIN_DIR/$SERVICE_NAME" > "$SERVICE_DIR/$SERVICE_NAME"

systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE_NAME"
echo "Service installed and started: $SERVICE_NAME"

# Install theme-set hook (keeps the restorable wallpaper reference current)
omarchy hook install theme-set "$PLUGIN_DIR/spotify-wallpaper-theme-hook.sh"
echo "Theme-set hook installed"

echo ""
echo "Done. Enable the bar widget if it is not already visible:"
echo ""
echo "  omarchy plugin enable $PLUGIN_ID"
echo ""
echo "Then click the disc-album icon in the bar to open settings."
