#!/bin/bash
# spotify-wallpaper.sh — Set currently playing Spotify album art as desktop wallpaper.
# Reads settings from ~/.config/omarchy/shell.json (the source of truth).
# Settings: enabled, cropMode, showTrackInfo, resetOnClose, blurEffect
set -euo pipefail

# The plugin ID is the name of the folder this script lives in, so renames of
# the plugin ID stay in sync automatically.
PLUGIN_ID="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"

STATE_DIR="$HOME/.local/state/omarchy/spotify-wallpaper"
CACHE_DIR="$HOME/.cache/omarchy/spotify-wallpaper"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
THEME_COLORS="$HOME/.local/state/omarchy/current/theme/colors.toml"
THEME_WALLPAPER_FILE="$STATE_DIR/theme-wallpaper"
ORIGINAL_FILE="$STATE_DIR/original-wallpaper"
LAST_ART_FILE="$STATE_DIR/last-art-url"
LAST_SETTINGS_FILE="$STATE_DIR/last-settings"
LAST_TRACK_FILE="$STATE_DIR/last-track-key"
THEME_MTIME_FILE="$STATE_DIR/theme-mtime"
BACKGROUND_LINK="$HOME/.local/state/omarchy/current/background"
POLL_INTERVAL=2

mkdir -p "$STATE_DIR" "$CACHE_DIR"

log() {
    printf '[spotify-wallpaper] %s\n' "$*" >&2
}

ACTIVE_PLAYER=""

detect_playing_player() {
    # Track any MPRIS player with "spotify" in its name (official client,
    # Omarchy Spotify, ...). Multiple can be registered at once; prefer the
    # one that is actually playing.
    local players p status
    players=$(playerctl -l 2>/dev/null || true)
    ACTIVE_PLAYER=""
    while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        case "$(echo "$p" | tr '[:upper:]' '[:lower:]')" in
            *spotify*) ;;
            *) continue ;;
        esac
        status=$(playerctl -p "$p" status 2>/dev/null || true)
        if [[ "$status" == "Playing" ]]; then
            ACTIVE_PLAYER="$p"
            return
        fi
    done <<< "$players"
}

theme_changed() {
    local current_mtime
    current_mtime=$(stat -c %Y "$THEME_COLORS" 2>/dev/null || echo 0)
    local saved_mtime=0
    if [[ -f "$THEME_MTIME_FILE" ]]; then
        saved_mtime=$(cat "$THEME_MTIME_FILE" 2>/dev/null || echo 0)
    fi
    if [[ "$current_mtime" != "$saved_mtime" ]]; then
        printf '%s' "$current_mtime" > "$THEME_MTIME_FILE"
        if [[ "$saved_mtime" != "0" ]]; then
            return 0
        fi
    fi
    return 1
}

read_config() {
    # A plugin whose widget is not in the bar layout is disabled: this covers
    # `omarchy plugin disable`, which removes the entry from the layout.
    local enabled="false"
    local crop_mode="fullscreen"
    local show_track_info="true"
    local reset_on_close="true"
    local blur_effect="false"
    if [[ -f "$SHELL_JSON" ]]; then
        local line
        line=$(jq -r --arg id "$PLUGIN_ID" '
            ([.bar.layout.left, .bar.layout.center, .bar.layout.right] | flatten
             | map(select(.id == $id)) | .[0]) // empty
            | [(.enabled // "On"), (.cropMode // "fullscreen"),
               (.showTrackInfo // "On"), (.resetOnClose // "On"), (.blurEffect // "Off")] | @tsv
        ' "$SHELL_JSON" 2>/dev/null || true)
        if [[ -n "$line" ]]; then
            IFS=$'\t' read -r enabled crop_mode show_track_info reset_on_close blur_effect <<< "$line"
        fi
    fi
    [[ "$enabled" == "On" || "$enabled" == "true" ]] && enabled="true" || enabled="false"
    [[ "$show_track_info" == "On" || "$show_track_info" == "true" ]] && show_track_info="true" || show_track_info="false"
    [[ "$reset_on_close" == "On" || "$reset_on_close" == "true" ]] && reset_on_close="true" || reset_on_close="false"
    [[ "$blur_effect" == "On" || "$blur_effect" == "true" ]] && blur_effect="true" || blur_effect="false"
    printf '%s\n%s\n%s\n%s\n%s\n' "$enabled" "$crop_mode" "$show_track_info" "$reset_on_close" "$blur_effect"
}

get_theme_color() {
    local key="$1"
    local fallback="$2"
    local color
    color=$(grep "^${key} = " "$THEME_COLORS" 2>/dev/null | head -1 | sed 's/.*= *"//' | sed 's/"//' || true)
    color="${color:-$fallback}"
    printf '%s' "$color"
}

get_screen_dimensions() {
    # Use the largest connected monitor by area so the rendered wallpaper
    # covers every output.
    local dims=""
    dims=$(hyprctl monitors -j 2>/dev/null | jq -r 'sort_by(.width * .height) | last | "\(.width)x\(.height)"' 2>/dev/null || true)
    if [[ -z "$dims" ]]; then
        dims="1920x1080"
        log "Warning: could not detect screen resolution, defaulting to $dims"
    fi
    printf '%s' "$dims"
}

resolve_font() {
    # Resolve the current Omarchy font to a font file path ImageMagick can use.
    local family file
    family=$(omarchy font current 2>/dev/null || true)
    if [[ -n "$family" ]]; then
        file=$(fc-match -f '%{file}' "$family" 2>/dev/null || true)
        if [[ -n "$file" && -f "$file" ]]; then
            printf '%s' "$file"
            return
        fi
    fi
    file=$(fc-match -f '%{file}' "monospace" 2>/dev/null || true)
    printf '%s' "$file"
}

sanitize_text() {
    # ImageMagick treats a leading @ as a file reference on some versions.
    local text="$1"
    if [[ "$text" == @* ]]; then
        text=" $text"
    fi
    printf '%s' "$text"
}

is_cached_art() {
    local path="$1"
    [[ "$path" == "$CACHE_DIR"/* ]]
}

capture_theme_wallpaper() {
    local current
    current=$(readlink -f "$BACKGROUND_LINK" 2>/dev/null || true)
    if [[ -n "$current" ]] && [[ -f "$current" ]] && ! is_cached_art "$current"; then
        printf '%s' "$current" > "$THEME_WALLPAPER_FILE"
    elif [[ ! -f "$THEME_WALLPAPER_FILE" ]]; then
        local theme_name
        theme_name=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)
        if [[ -n "$theme_name" ]]; then
            local found
            found=$(find -L "$HOME/.local/state/omarchy/current/theme/backgrounds" \
                "$HOME/.config/omarchy/backgrounds/$theme_name" \
                -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
                2>/dev/null | sort | head -1 || true)
            if [[ -n "$found" ]]; then
                printf '%s' "$found" > "$THEME_WALLPAPER_FILE"
                log "Found theme wallpaper from theme directory: $found"
            fi
        fi
    fi
}

process_image() {
    local input="$1"
    local crop_mode="$2"
    local url_hash="$3"
    local show_info="$4"
    local artist="$5"
    local album="$6"
    local title="$7"
    local blur_effect="$8"

    local bg_color
    bg_color=$(get_theme_color "background" "#1e1e2e")
    local fg_color
    fg_color=$(get_theme_color "foreground" "#cdd6f4")
    local dim_fg_color
    dim_fg_color=$(get_theme_color "dark_foreground" "#9aa1b7")

    local screen_dims
    screen_dims=$(get_screen_dimensions)
    local screen_w="${screen_dims%x*}"
    local screen_h="${screen_dims#*x}"

    local blur_radius=$(( screen_h * 40 / 1080 ))
    [[ $blur_radius -lt 12 ]] && blur_radius=12

    # When track details are shown, the text is baked into the image, so the
    # processed cache key must include the track text — otherwise a same-album
    # track change would reuse the image with the previous track's title.
    # v4: fix pill alpha order (was drawn fully opaque, not 50% black).
    local settings_key="${crop_mode}_${blur_effect}_${show_info}_v4"
    if [[ "$show_info" == "true" ]]; then
        local track_hash
        track_hash=$(printf '%s' "${artist}|${album}|${title}" | md5sum | cut -d' ' -f1)
        settings_key="${settings_key}_${track_hash}"
    fi
    local output="$CACHE_DIR/${url_hash}_${settings_key}.jpg"

    if [[ -f "$output" ]]; then
        printf '%s' "$output"
        return
    fi

    local magick_args=()

    local image_size=0

    case "$crop_mode" in
        fullscreen)
            magick_args+=("$input" -resize "${screen_w}x${screen_h}^" -gravity center -extent "${screen_w}x${screen_h}")
            if [[ "$blur_effect" == "true" ]]; then
                magick_args+=(-blur "0x$(( blur_radius / 2 ))")
            fi
            ;;
        centered-75)
            local target_size
            target_size=$(( screen_w < screen_h ? screen_w : screen_h ))
            target_size=$(( target_size * 75 / 100 ))
            image_size=$target_size
            if [[ "$blur_effect" == "true" ]]; then
                # Blurred, screen-filling copy of the art as the backdrop,
                # dimmed with 50% black; the sharp art is composited centered
                # on top of it.
                magick_args+=(
                    "(" "$input" -resize "${screen_w}x${screen_h}^" -gravity center -extent "${screen_w}x${screen_h}" -blur "0x${blur_radius}" -fill "#000000" -colorize 30 ")"
                    "(" "$input" -resize "${target_size}x${target_size}" ")"
                    -background "$bg_color" -gravity center -composite
                )
            else
                magick_args+=("$input" -resize "${target_size}x${target_size}" -background "$bg_color" -gravity center -extent "${screen_w}x${screen_h}")
            fi
            ;;
        centered-native)
            local img_w img_h
            img_w=$(magick identify -format '%w' "$input" 2>/dev/null || echo 0)
            img_h=$(magick identify -format '%h' "$input" 2>/dev/null || echo 0)
            image_size=$(( img_w < img_h ? img_w : img_h ))
            if [[ "$blur_effect" == "true" ]]; then
                magick_args+=(
                    "(" "$input" -resize "${screen_w}x${screen_h}^" -gravity center -extent "${screen_w}x${screen_h}" -blur "0x${blur_radius}" -fill "#000000" -colorize 30 ")"
                    "(" "$input" ")"
                    -background "$bg_color" -gravity center -composite
                )
            else
                magick_args+=("$input" -background "$bg_color" -gravity center -extent "${screen_w}x${screen_h}")
            fi
            ;;
        *)
            magick_args+=("$input")
            ;;
    esac

    if [[ "$show_info" == "true" && -n "$title" ]]; then
        local esc_artist esc_album esc_title
        esc_artist=$(sanitize_text "$artist")
        esc_album=$(sanitize_text "$album")
        esc_title=$(sanitize_text "$title")

        local font_name
        font_name=$(resolve_font)
        if [[ -z "$font_name" ]]; then
            log "Warning: could not resolve a font file; skipping track info"
        else
        local title_size=$(( screen_h * 20 / 1080 ))
        [[ $title_size -lt 13 ]] && title_size=13
        local sub_size=$(( screen_h * 15 / 1080 ))
        [[ $sub_size -lt 10 ]] && sub_size=10
        local line_gap=$(( screen_h * 12 / 1080 ))
        [[ $line_gap -lt 6 ]] && line_gap=6
        local bottom_margin=$(( screen_h * 50 / 1080 ))
        [[ $bottom_margin -lt 30 ]] && bottom_margin=30

        if [[ "$crop_mode" == "fullscreen" ]]; then
            local info_text="${esc_artist}  -  ${esc_album}"
            local pill_pad_x=$(( screen_h * 40 / 1080 ))
            [[ $pill_pad_x -lt 20 ]] && pill_pad_x=20
            local pill_pad_y=$(( screen_h * 16 / 1080 ))
            [[ $pill_pad_y -lt 8 ]] && pill_pad_y=8
            local pill_gap=$(( screen_h * 10 / 1080 ))
            [[ $pill_gap -lt 5 ]] && pill_gap=5
            local pill_radius=$(( screen_h * 16 / 1080 ))
            [[ $pill_radius -lt 8 ]] && pill_radius=8

            local title_w sub_w pill_w pill_h title_pill_y sub_pill_y
            title_w=$(magick -font "$font_name" -pointsize "$title_size" label:"$esc_title" -format '%w' info: 2>/dev/null || echo 200)
            sub_w=$(magick -font "$font_name" -pointsize "$sub_size" label:"$info_text" -format '%w' info: 2>/dev/null || echo 200)
            pill_w=$(( title_w > sub_w ? title_w : sub_w ))
            pill_w=$(( pill_w + pill_pad_x * 2 ))
            pill_h=$(( title_size + line_gap + sub_size + pill_pad_y * 2 ))
            local pill_x=$(( (screen_w - pill_w) / 2 ))
            local pill_y=$(( screen_h - pill_h - bottom_margin ))
            title_pill_y=$(( pill_y + pill_pad_y ))
            sub_pill_y=$(( pill_y + pill_pad_y + title_size + line_gap ))

            magick_args+=(
                "(" -size "${pill_w}x${pill_h}" xc:none -fill "#000000"
                -draw "roundRectangle 0,0 $((pill_w-1)),$((pill_h-1)) $pill_radius,$pill_radius"
                -alpha set -channel A -evaluate multiply 0.5 +channel ")"
                -gravity northwest -geometry "+${pill_x}+${pill_y}" -composite
                -font "$font_name" -fill "$fg_color" -pointsize "$title_size" -gravity north
                -annotate "+0+$title_pill_y" "$esc_title"
                -fill "$dim_fg_color" -pointsize "$sub_size" -gravity north
                -annotate "+0+$sub_pill_y" "$info_text"
            )
        else
            local image_top image_bottom
            if [[ $image_size -gt 0 ]]; then
                image_top=$(( (screen_h - image_size) / 2 ))
                image_bottom=$(( image_top + image_size ))
            else
                image_top=0
                image_bottom=0
            fi

            local text_block_h=$(( title_size + line_gap + sub_size ))
            local text_top=$(( image_bottom + bottom_margin ))

            if [[ $(( text_top + text_block_h )) -gt $screen_h ]]; then
                text_top=$(( screen_h - text_block_h - bottom_margin ))
            fi

            magick_args+=(
                -font "$font_name" -fill "$fg_color" -pointsize "$title_size" -gravity north
                -annotate "+0+$text_top" "$esc_title"
                -fill "$dim_fg_color" -pointsize "$sub_size" -gravity north
                -annotate "+0+$(( text_top + title_size + line_gap ))" "$esc_artist  -  $esc_album"
            )
        fi
        fi
    fi

    magick_args+=(-quality 90 "$output")

    if magick "${magick_args[@]}" 2>/dev/null; then
        printf '%s' "$output"
    else
        log "Warning: image processing failed, using raw art"
        printf '%s' "$input"
    fi
}

save_original() {
    if [[ ! -f "$ORIGINAL_FILE" ]]; then
        local current
        current=$(readlink -f "$BACKGROUND_LINK" 2>/dev/null || true)
        if [[ -n "$current" ]] && [[ -f "$current" ]] && ! is_cached_art "$current"; then
            printf '%s' "$current" > "$ORIGINAL_FILE"
            printf '%s' "$current" > "$THEME_WALLPAPER_FILE"
            log "Saved original wallpaper: $current"
        elif [[ -f "$THEME_WALLPAPER_FILE" ]]; then
            local theme_wp
            theme_wp=$(cat "$THEME_WALLPAPER_FILE")
            if [[ -n "$theme_wp" ]] && [[ -f "$theme_wp" ]]; then
                printf '%s' "$theme_wp" > "$ORIGINAL_FILE"
                log "Using persistent theme wallpaper: $theme_wp"
            else
                log "Warning: persistent theme wallpaper file is invalid"
            fi
        else
            log "Warning: no original wallpaper reference available"
        fi
    fi
}

restore_wallpaper() {
    local restore_path=""
    if [[ -f "$ORIGINAL_FILE" ]]; then
        restore_path=$(cat "$ORIGINAL_FILE")
    elif [[ -f "$THEME_WALLPAPER_FILE" ]]; then
        restore_path=$(cat "$THEME_WALLPAPER_FILE")
        log "Using persistent theme wallpaper as fallback"
    fi
    if [[ -n "$restore_path" ]] && [[ -f "$restore_path" ]]; then
        omarchy theme bg set "$restore_path"
        log "Restored original wallpaper: $restore_path"
    else
        log "Warning: no original wallpaper to restore"
    fi
    rm -f "$ORIGINAL_FILE" "$LAST_ART_FILE" "$LAST_SETTINGS_FILE" "$LAST_TRACK_FILE"
    # Defer cache cleanup: the shell's background transition may still be
    # reading the just-replaced image. Deleting it immediately races the fade.
    (sleep 5; rm -f "$CACHE_DIR"/*.jpg) &
}

set_album_art() {
    local art_url="$1"
    local crop_mode="$2"
    local show_info="$3"
    local blur_effect="$4"
    local artist="$5"
    local album="$6"
    local title="$7"

    local track_key="${art_url}|${artist}|${album}|${title}"
    local settings_key="${crop_mode}_${blur_effect}_${show_info}"

    if [[ -f "$LAST_ART_FILE" ]] && [[ "$(cat "$LAST_ART_FILE")" == "$art_url" ]] && \
       [[ -f "$LAST_SETTINGS_FILE" ]] && [[ "$(cat "$LAST_SETTINGS_FILE")" == "$settings_key" ]] && \
       [[ -f "$LAST_TRACK_FILE" ]] && [[ "$(cat "$LAST_TRACK_FILE")" == "$track_key" ]]; then
        return
    fi

    # With track details off, the rendered wallpaper depends only on the art —
    # a same-album track change must not trigger an update at all.
    if [[ "$show_info" != "true" ]] && [[ -f "$LAST_ART_FILE" ]] && \
       [[ "$(cat "$LAST_ART_FILE")" == "$art_url" ]] && \
       [[ -f "$LAST_SETTINGS_FILE" ]] && [[ "$(cat "$LAST_SETTINGS_FILE")" == "$settings_key" ]]; then
        printf '%s' "$track_key" > "$LAST_TRACK_FILE"
        return
    fi

    local raw_dest=""

    if [[ "$art_url" == https://* ]] || [[ "$art_url" == http://* ]]; then
        local url_hash
        url_hash=$(printf '%s' "$art_url" | md5sum | cut -d' ' -f1)
        local cache_file="$CACHE_DIR/${url_hash}.jpg"
        if [[ ! -f "$cache_file" ]]; then
            if ! curl -sL --fail --max-time 10 "$art_url" -o "$cache_file" 2>/dev/null; then
                log "Warning: failed to download album art from $art_url"
                return
            fi
        fi
        raw_dest="$cache_file"
    elif [[ "$art_url" == file://* ]]; then
        raw_dest="${art_url#file://}"
        if [[ ! -f "$raw_dest" ]]; then
            log "Warning: local art file does not exist: $raw_dest"
            return
        fi
    else
        log "Warning: unrecognized art URL format: $art_url"
        return
    fi

    if [[ -n "$raw_dest" ]] && [[ -f "$raw_dest" ]]; then
        local url_hash
        url_hash=$(printf '%s' "$art_url" | md5sum | cut -d' ' -f1)
        local final_dest
        final_dest=$(process_image "$raw_dest" "$crop_mode" "$url_hash" "$show_info" "$artist" "$album" "$title" "$blur_effect")
        if [[ -n "$final_dest" ]] && [[ -f "$final_dest" ]]; then
            omarchy theme bg set "$final_dest"
            printf '%s' "$art_url" > "$LAST_ART_FILE"
            printf '%s' "$settings_key" > "$LAST_SETTINGS_FILE"
            printf '%s' "$track_key" > "$LAST_TRACK_FILE"
            log "Set album art as wallpaper: $title - $artist (crop: $crop_mode, info: $show_info, blur: $blur_effect)"
        fi
    fi
}

if [[ "${1:-}" == "--reset" ]]; then
    log "Manual reset requested"
    restore_wallpaper
    exit 0
fi

capture_theme_wallpaper

spotify_playing=false
was_enabled=true
prev_settings_key=""

while true; do
    config_output=$(read_config)
    config_enabled=$(echo "$config_output" | sed -n '1p')
    config_crop=$(echo "$config_output" | sed -n '2p')
    config_show_info=$(echo "$config_output" | sed -n '3p')
    config_reset_on_close=$(echo "$config_output" | sed -n '4p')
    config_blur=$(echo "$config_output" | sed -n '5p')

    current_settings_key="${config_crop}_${config_blur}_${config_show_info}"

    if [[ "$config_enabled" != "true" ]]; then
        if $was_enabled; then
            was_enabled=false
            log "Plugin disabled — restoring original wallpaper"
            restore_wallpaper
            spotify_playing=false
        fi
        sleep "$POLL_INTERVAL"
        continue
    fi

    if ! $was_enabled; then
        was_enabled=true
        log "Plugin re-enabled"
    fi

    if [[ "$current_settings_key" != "$prev_settings_key" ]] && $spotify_playing; then
        log "Settings changed ($prev_settings_key -> $current_settings_key) — forcing wallpaper update"
        rm -f "$LAST_ART_FILE" "$LAST_SETTINGS_FILE" "$LAST_TRACK_FILE"
    fi
    prev_settings_key="$current_settings_key"

    if theme_changed && $spotify_playing; then
        log "Theme changed — clearing cache and forcing wallpaper update"
        rm -f "$LAST_ART_FILE" "$LAST_SETTINGS_FILE" "$LAST_TRACK_FILE"
        # Defer processed-image cleanup: the currently displayed wallpaper is
        # one of these files until the re-render below replaces it.
        (sleep 5; rm -f "$CACHE_DIR"/*_*.jpg) &
        capture_theme_wallpaper
    fi

    detect_playing_player

    if [[ -n "$ACTIVE_PLAYER" ]]; then
        if ! $spotify_playing; then
            spotify_playing=true
            save_original
            capture_theme_wallpaper
            theme_changed >/dev/null || true
            log "Spotify playing ($ACTIVE_PLAYER) — switching to album art wallpaper (crop: $config_crop, info: $config_show_info, blur: $config_blur)"
        fi

        art_url=$(playerctl -p "$ACTIVE_PLAYER" metadata mpris:artUrl 2>/dev/null || true)
        artist=$(playerctl -p "$ACTIVE_PLAYER" metadata xesam:artist 2>/dev/null || true)
        album=$(playerctl -p "$ACTIVE_PLAYER" metadata xesam:album 2>/dev/null || true)
        title=$(playerctl -p "$ACTIVE_PLAYER" metadata xesam:title 2>/dev/null || true)

        if [[ -n "$art_url" ]]; then
            set_album_art "$art_url" "$config_crop" "$config_show_info" "$config_blur" "$artist" "$album" "$title"
        fi
    else
        if $spotify_playing; then
            spotify_playing=false
            if [[ "$config_reset_on_close" == "true" ]]; then
                any_player=$(playerctl -l 2>/dev/null | grep -i spotify | head -1 || true)
                if [[ -z "$any_player" ]]; then
                    log "Spotify closed — restoring original wallpaper"
                else
                    log "Spotify paused/stopped — restoring original wallpaper"
                fi
                restore_wallpaper
            else
                log "Playback stopped — keeping current wallpaper (resetOnClose disabled)"
                rm -f "$LAST_ART_FILE" "$LAST_SETTINGS_FILE" "$LAST_TRACK_FILE"
            fi
        fi
    fi

    sleep "$POLL_INTERVAL"
done
