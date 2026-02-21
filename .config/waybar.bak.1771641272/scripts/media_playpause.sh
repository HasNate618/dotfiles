#!/usr/bin/env bash
status="$(playerctl status 2>/dev/null || true)"
if [ "$status" = "Playing" ]; then
  icon=""
else
  icon=""
fi
printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$icon" "Play/Pause" "media-playpause"
