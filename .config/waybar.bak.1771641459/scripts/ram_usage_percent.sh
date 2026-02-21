#!/usr/bin/env bash
set -u

escape_json() {
  printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\\"/g'
}

# Read total and available memory in kB
if [ -r /proc/meminfo ]; then
  total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  avail_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
else
  # fallback to free -k
  read total_kb used_kb free_kb shared_kb buff_kb cache_kb avail_kb <<< $(free -k | awk '/^Mem:/ {print $2, $3, $4, $5, $6, $7, $7}')
fi

if [ -z "$total_kb" ] || [ "$total_kb" -eq 0 ] 2>/dev/null; then
  percent=0
  used_gb="0.0"
  total_gb="0.0"
else
  used_kb=$((total_kb - avail_kb))
  percent=$(awk -v t="$total_kb" -v u="$used_kb" 'BEGIN{ if(t>0) printf "%d", (u*100 + t/2)/t; else print 0 }')
  used_gb=$(awk -v u="$used_kb" 'BEGIN{printf "%.1f", u/1024/1024}')
  total_gb=$(awk -v t="$total_kb" 'BEGIN{printf "%.1f", t/1024/1024}')
fi

icon=$'\uEFC5'
text="${percent}% ${icon}"
tooltip="${used_gb}GB / ${total_gb}GB (${percent}%)"

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$(escape_json "$text")" "$(escape_json "$tooltip")" "ram"
