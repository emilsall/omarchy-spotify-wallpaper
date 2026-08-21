#!/bin/bash
# uninstall.sh — Remove the Spotify Album Wallpaper background service and hook.
# Run this before `omarchy plugin remove` (or any time you want to tear down
# the service without removing the plugin folder).
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="omarchy-spotify-wallpaper.service"
SERVICE_DIR="$HOME/.config/systemd/user"
HOOK_FILE="$HOME/.config/omarchy/hooks/theme-set.d/spotify-wallpaper-theme-hook.sh"
STATE_DIR="$HOME/.local/state/omarchy/spotify-wallpaper"
CACHE_DIR="$HOME/.cache/omarchy/spotify-wallpaper"

# Stop the service first so it cannot re-apply album art after the reset
systemctl --user disable --now "$SERVICE_NAME" 2>/dev/null || true
rm -f "$SERVICE_DIR/$SERVICE_NAME"
systemctl --user daemon-reload
echo "Service removed: $SERVICE_NAME"

# Remove the plugin-owned album-art layer now that the service is stopped.
"$PLUGIN_DIR/spotify-wallpaper.sh" --reset || true

rm -f "$HOOK_FILE"
echo "Theme-set hook removed"

rm -rf "$STATE_DIR" "$CACHE_DIR"
echo "State and cache cleaned"

echo ""
echo "Done. To remove the bar widget as well:"
echo ""
echo "  omarchy plugin remove $(basename "$PLUGIN_DIR")"
