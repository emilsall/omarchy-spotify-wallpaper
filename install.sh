#!/bin/bash
# install.sh — Set up the Spotify Album Wallpaper plugin's background service.
#
# Run this once after `omarchy plugin add`. It installs a systemd user service
# that watches Spotify playback and a theme-set hook that keeps the original
# wallpaper reference up to date.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="$(basename "$PLUGIN_DIR")"
SERVICE_NAME="omarchy-spotify-wallpaper.service"
SERVICE_DIR="$HOME/.config/systemd/user"

echo "Installing Spotify Album Wallpaper ($PLUGIN_ID)"

# Check dependencies
missing=()
for cmd in playerctl jq magick curl; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done

if (( ${#missing[@]} > 0 )); then
  echo ""
  echo "Missing required dependencies: ${missing[*]}"
  echo "Install them with:"
  echo ""
  pkgs=()
  for cmd in "${missing[@]}"; do
    case "$cmd" in
      magick) pkgs+=("imagemagick") ;;
      *)      pkgs+=("$cmd") ;;
    esac
  done
  echo "  omarchy pkg add ${pkgs[*]}"
  echo ""
  exit 1
fi

# Install systemd user service
mkdir -p "$SERVICE_DIR"
sed "s|%h/.config/omarchy/plugins/emil.spotify-wallpaper|%h/.config/omarchy/plugins/$PLUGIN_ID|" \
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
