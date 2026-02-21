#!/usr/bin/env bash

set -u

action="${1:-}"
preferred_player="playerctld"

run_playerctl() {
  local cmd=("$@")
  playerctl -p "$preferred_player" "${cmd[@]}" 2>/dev/null || playerctl "${cmd[@]}" 2>/dev/null
}

case "$action" in
  prev)
    run_playerctl previous
    ;;
  playpause)
    run_playerctl play-pause
    ;;
  next)
    run_playerctl next
    ;;
  seek-back)
    run_playerctl position 5-
    ;;
  seek-forward)
    run_playerctl position 5+
    ;;
  open-cover)
    cover_path="/tmp/waybar/cover.png"
    if [ -f "$cover_path" ]; then
      xdg-open "$cover_path" >/dev/null 2>&1 &
    else
      art_url="$(run_playerctl metadata mpris:artUrl | head -n 1)"
      if [ -n "${art_url:-}" ]; then
        if [[ "$art_url" == file://* ]]; then
          art_url="${art_url#file://}"
        fi
        xdg-open "$art_url" >/dev/null 2>&1 &
      fi
    fi
    ;;
  *)
    exit 0
    ;;
esac
