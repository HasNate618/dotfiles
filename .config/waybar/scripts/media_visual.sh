#!/usr/bin/env bash
set -u

CAVA_RAW="/tmp/waybar/cava.raw"
COVER_DIR="/tmp/waybar"
mkdir -p "$COVER_DIR"

# Try to start cava (raw output) if available and supported
if command -v cava >/dev/null 2>&1; then
  # only attempt if cava supports a raw output driver (avoid invalid option)
  if cava --help 2>&1 | grep -qi raw; then
    # start cava in background if not already
    if ! pgrep -f "cava .* -o raw" >/dev/null 2>&1 && ! pgrep -f "cava -o raw" >/dev/null 2>&1; then
      nohup cava -o raw >"$CAVA_RAW" 2>/tmp/waybar/cava.err &
      sleep 0.05
    fi
  else
    # log that cava doesn't support raw output on this system
    echo "cava installed but lacks raw output support; skipping" > /tmp/waybar/cava.err 2>/dev/null || true
  fi
fi

# If cava raw data exists, parse last line into small block-visual
if [ -f "$CAVA_RAW" ] && [ -s "$CAVA_RAW" ]; then
  line="$(tail -n 1 "$CAVA_RAW" 2>/dev/null || true)"
  if [ -n "$line" ]; then
    read -r -a nums <<< "$line"
    blocks=( "▁" "▂" "▃" "▄" "▅" "▆" "▇" "█" )
    out=""
    max=6
    for i in $(seq 0 $((max-1))); do
      n=${nums[i]:-0}
      if [[ "$n" =~ ^[0-9]+$ ]]; then
        idx=$(( n % 8 ))
      else
        idx=0
      fi
      out+="${blocks[$idx]}"
    done
    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$out" "Visualizer" "media-visual"
    exit 0
  fi
fi

# Fallback: show a small progress-style bar based on current track position
player="$(playerctl -l 2>/dev/null | head -n1 || true)"
if [ -n "$player" ]; then
  pos="$(playerctl -p "$player" position 2>/dev/null || echo 0)"
  len_us="$(playerctl -p "$player" metadata mpris:length 2>/dev/null || echo 0)"
  length_sec=0
  if [[ "$len_us" =~ ^[0-9]+$ ]] && [ "$len_us" -gt 0 ]; then
    length_sec=$(( len_us / 1000000 ))
  fi
  pct=0
  if [ "$length_sec" -gt 0 ]; then
    pct=$(awk -v p="$pos" -v l="$length_sec" 'BEGIN{printf "%d", (p/l)*100}')
  fi
  filled=$(( (pct * 6) / 100 ))
  out=""
  for i in $(seq 1 $filled); do out+="▇"; done
  for i in $(seq 1 $((6 - filled))); do out+="▁"; done
  printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$out" "Progress" "media-visual"
  exit 0
fi

# Nothing playing
printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "󰝚" "No media" "media-visual"
