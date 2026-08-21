#!/bin/bash
# theme-set hook for spotify-wallpaper — saves the new theme's background path
# so the wallpaper script can restore it even after service restarts.
STATE_DIR="$HOME/.local/state/omarchy/spotify-wallpaper"
THEME_WALLPAPER_FILE="$STATE_DIR/theme-wallpaper"
BACKGROUND_LINK="$HOME/.local/state/omarchy/current/background"
CACHE_DIR="$HOME/.cache/omarchy/spotify-wallpaper"

mkdir -p "$STATE_DIR"

current=$(readlink -f "$BACKGROUND_LINK" 2>/dev/null || true)
if [[ -n "$current" ]] && [[ -f "$current" ]]; then
    case "$current" in
        "$CACHE_DIR"/*) ;;
        *) printf '%s' "$current" > "$THEME_WALLPAPER_FILE" ;;
    esac
fi
