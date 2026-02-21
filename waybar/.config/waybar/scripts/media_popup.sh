#!/usr/bin/env bash

# Toggle the media popup Python script
PY_SCRIPT="/home/nate/.config/waybar/scripts/media_popup.py"
PID=$(pgrep -f "${PY_SCRIPT}" | head -n1 || true)
if [ -n "$PID" ]; then
  kill "$PID" 2>/dev/null || true
  exit 0
else
  # start detached
  nohup python3 "$PY_SCRIPT" >/dev/null 2>&1 &
  exit 0
fi
