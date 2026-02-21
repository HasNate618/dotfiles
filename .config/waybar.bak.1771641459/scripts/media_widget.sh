#!/usr/bin/env bash

set -u

ICON_NOTE="󰝚"

escape_json() {
  printf '%s' "$1" | sed ':a;N;$!ba;s/\\/\\\\/g;s/"/\\"/g;s/\n/\\n/g'
}

format_time() {
  local total="${1:-0}"
  local h m s

  if ! [[ "$total" =~ ^[0-9]+$ ]]; then
    total=0
  fi

  h=$((total / 3600))
  m=$(((total % 3600) / 60))
  s=$((total % 60))

  if [ "$h" -gt 0 ]; then
    printf "%d:%02d:%02d" "$h" "$m" "$s"
  else
    printf "%d:%02d" "$m" "$s"
  fi
}

build_bar() {
  local pct="${1:-0}"
  local slots=18
  local filled i bar

  filled="$(awk -v p="$pct" -v s="$slots" 'BEGIN{f=int((p/100)*s+0.5); if(f<0)f=0; if(f>s)f=s; print f}')"
  bar="["
  i=0
  while [ "$i" -lt "$slots" ]; do
    if [ "$i" -lt "$filled" ]; then
      bar="${bar}#"
    else
      bar="${bar}-"
    fi
    i=$((i + 1))
  done
  bar="${bar}]"
  printf '%s' "$bar"
}

pick_player() {
  local first="" player="" status=""
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

if ! command -v playerctl >/dev/null 2>&1; then
  printf '{"text":"%s","tooltip":"%s","class":"stopped"}\n' "$ICON_NOTE" "playerctl not installed"
  exit 0
fi

player="$(pick_player || true)"
if [ -z "$player" ]; then
  printf '{"text":"%s","tooltip":"%s","class":"stopped"}\n' "$ICON_NOTE" "No active media player"
  exit 0
fi

status="$(playerctl -p "$player" status 2>/dev/null || echo "Stopped")"
title="$(playerctl -p "$player" metadata xesam:title 2>/dev/null || true)"
artist="$(playerctl -p "$player" metadata xesam:artist 2>/dev/null | head -n 1 || true)"
album="$(playerctl -p "$player" metadata xesam:album 2>/dev/null || true)"
art_url="$(playerctl -p "$player" metadata mpris:artUrl 2>/dev/null || true)"
# cache/download cover image for the GTK menu image (/tmp/waybar/cover.png)
cover_dir="/tmp/waybar"
cover_path="$cover_dir/cover.png"
mkdir -p "$cover_dir"
if [ -n "$art_url" ]; then
  prev_url="$(cat "$cover_dir/cover_url" 2>/dev/null || true)"
  if [ "$art_url" != "$prev_url" ]; then
    if [[ "$art_url" == file://* ]]; then
      src="${art_url#file://}"
      [ -f "$src" ] && cp -f "$src" "$cover_path" 2>/dev/null || true
    elif [[ "$art_url" =~ ^https?:// ]]; then
      if command -v curl >/dev/null 2>&1; then
        curl -sL --fail "$art_url" -o "$cover_path" 2>/dev/null || true
      elif command -v wget >/dev/null 2>&1; then
        wget -qO "$cover_path" "$art_url" 2>/dev/null || true
      fi
    fi
    printf '%s' "$art_url" > "$cover_dir/cover_url"
  fi
fi
position_raw="$(playerctl -p "$player" position 2>/dev/null || echo "0")"
length_us="$(playerctl -p "$player" metadata mpris:length 2>/dev/null || echo "0")"

[ -z "${title:-}" ] && title="Nothing playing"
[ "$artist" = "(null)" ] && artist=""
[ "$album" = "(null)" ] && album=""

position_sec="$(awk -v p="$position_raw" 'BEGIN{if(p<0)p=0; printf "%d", p}')"
length_sec=0
if [[ "$length_us" =~ ^[0-9]+$ ]] && [ "$length_us" -gt 0 ]; then
  length_sec=$((length_us / 1000000))
fi

progress_pct=0
if [ "$length_sec" -gt 0 ]; then
  progress_pct="$(awk -v p="$position_sec" -v l="$length_sec" 'BEGIN{if(l<=0){print 0}else{v=(p/l)*100; if(v>100)v=100; if(v<0)v=0; printf "%.0f", v}}')"
fi

timeline="$(build_bar "$progress_pct")"
pos_fmt="$(format_time "$position_sec")"
len_fmt="$(format_time "$length_sec")"

status_icon="■"
status_class="$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')"
if [ "$status" = "Playing" ]; then
  status_icon="▶"
elif [ "$status" = "Paused" ]; then
  status_icon="⏸"
fi

tooltip="${status_icon} ${title}"
if [ -n "$artist" ]; then
  tooltip="${tooltip}\n${artist}"
fi
if [ -n "$album" ]; then
  tooltip="${tooltip}\nAlbum: ${album}"
fi
if [ "$length_sec" -gt 0 ]; then
  tooltip="${tooltip}\n${pos_fmt} / ${len_fmt}\n${timeline}"
fi
if [ -n "$art_url" ]; then
  tooltip="${tooltip}\nCover: menu -> Open Album Cover"
fi
tooltip="${tooltip}\nControls: menu/click, middle=play-pause, scroll=seek"

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
  "$(escape_json "$ICON_NOTE")" \
  "$(escape_json "$tooltip")" \
  "$(escape_json "$status_class")"
