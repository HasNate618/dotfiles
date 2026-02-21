#!/usr/bin/env bash
set -u

escape_json() {
  printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

pct=""
muted="false"

if command -v wpctl >/dev/null 2>&1; then
  out="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)"
  if [ -n "$out" ]; then
    vol="$(printf "%s" "$out" | awk '{print $2}')"
    if printf "%s" "$out" | grep -q '\[MUTED\]'; then
      muted="true"
    fi
    if printf "%s" "$vol" | grep -qE '^[0-9]+([.][0-9]+)?$'; then
      pct="$(awk -v v="$vol" 'BEGIN{p=int((v*100)+0.5); if (p<0) p=0; printf "%d", p}')"
    fi
  fi
fi

if [ -z "$pct" ] && command -v pamixer >/dev/null 2>&1; then
  p="$(pamixer --get-volume 2>/dev/null || true)"
  if printf "%s" "$p" | grep -qE '^[0-9]+$'; then
    pct="$p"
  fi
  m="$(pamixer --get-mute 2>/dev/null || true)"
  if [ "$m" = "true" ]; then
    muted="true"
  fi
fi

if [ -z "$pct" ]; then
  pct="0"
fi

if [ "$muted" = "true" ] || [ "$pct" -le 0 ]; then
  icon=""
  class_name="muted"
elif [ "$pct" -lt 34 ]; then
  icon=""
  class_name="low"
elif [ "$pct" -lt 67 ]; then
  icon=""
  class_name="medium"
else
  icon=""
  class_name="high"
fi

text="${pct}% ${icon}"
tooltip="Volume ${pct}%"
if [ "$muted" = "true" ]; then
  tooltip="${tooltip} (muted)"
fi

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
  "$(escape_json "$text")" \
  "$(escape_json "$tooltip")" \
  "$class_name"
