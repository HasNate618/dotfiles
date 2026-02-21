#!/usr/bin/env bash
set -u

COVER_DIR="/tmp/waybar"
COVER_PATH="$COVER_DIR/cover.png"
COVER_URL_FILE="$COVER_DIR/cover_url"
ICON_NOTE="󰝚"
mkdir -p "$COVER_DIR"

pick_player() {
  local first="" player status
  while IFS= read -r player; do
    [ -z "$player" ] && continue
    [ -z "$first" ] && first="$player"
    status="$(playerctl -p "$player" status 2>/dev/null || true)"
    if [ "$status" = "Playing" ]; then
      printf '%s' "$player"
      return 0
    fi
  done < <(playerctl -l 2>/dev/null)
  if [ -n "$first" ]; then
    printf '%s' "$first"
    return 0
  fi
  return 1
}

player="$(pick_player || true)"
if [ -z "$player" ]; then
  printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$ICON_NOTE" "No active media player" "media-cover"
  exit 0
fi

art_url="$(playerctl -p "$player" metadata mpris:artUrl 2>/dev/null || true)"
if [ -n "$art_url" ]; then
  prev="$(cat "$COVER_URL_FILE" 2>/dev/null || true)"
  if [ "$art_url" != "$prev" ]; then
    if [[ "$art_url" == file://* ]]; then
      src="${art_url#file://}"
      [ -f "$src" ] && cp -f "$src" "$COVER_PATH" 2>/dev/null || true
    elif [[ "$art_url" =~ ^https?:// ]]; then
      if command -v curl >/dev/null 2>&1; then
        curl -sL --fail "$art_url" -o "$COVER_PATH" 2>/dev/null || true
      elif command -v wget >/dev/null 2>&1; then
        wget -qO "$COVER_PATH" "$art_url" 2>/dev/null || true
      fi
    fi
    printf '%s' "$art_url" > "$COVER_URL_FILE" 2>/dev/null || true
  fi
fi

if [ -f "$COVER_PATH" ]; then
  # Use CSS background-image to display cover; return empty text so Waybar doesn't show raw HTML
  printf '{"text":"","tooltip":"%s","class":"%s"}\n' "Cover" "media-cover has-cover"
else
  printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$ICON_NOTE" "No cover" "media-cover"
fi
