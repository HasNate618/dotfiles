#!/usr/bin/env bash
set -u

ICON_DISCHARGING="󰁹"
ICON_CHARGING="󰂅"
ICON_UNKNOWN="󰁺"
# Per-capacity icons (0..90 -> 10 entries)
DEFAULT_ICONS=("󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹")
CHARGING_ICONS=("󰢜" "󰂆" "󰂇" "󰂈" "󰢝" "󰂉" "󰢞" "󰂊" "󰂋" "󰂅")

format_hm() {
  local hours_float="$1"
  if [ -z "$hours_float" ]; then
    echo "--:--"
    return
  fi
  H=$(awk -v f="$hours_float" 'BEGIN{printf "%d", int(f)}')
  M=$(awk -v f="$hours_float" 'BEGIN{printf "%02d", int((f-int(f))*60)}')
  printf "%d:%02d" "$H" "$M"
}

find_bat_sysfs() {
  for d in /sys/class/power_supply/BAT*; do
    [ -d "$d" ] && { printf "%s" "$d"; return 0; }
  done
  return 1
}

escape_json() {
  # escape backslashes and double quotes
  printf "%s" "$1" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g'
}

BAT_SYSFS="$(find_bat_sysfs 2>/dev/null || true)"
status="Unknown"
capacity=""
tim="--:--"
power_w=""
icon="$ICON_UNKNOWN"

# Try upower for best info
if command -v upower >/dev/null 2>&1; then
  batpath=$(upower -e | grep -i battery | head -n1 || true)
  if [ -n "$batpath" ]; then
    info=$(upower -i "$batpath" 2>/dev/null || true)
    capacity=$(echo "$info" | awk -F': +' '/percentage:/ {gsub(/%/,"",$2); print $2; exit}')
    status=$(echo "$info" | awk -F': +' '/state:/ {print $2; exit}')
    timetxt=$(echo "$info" | awk -F': +' '/time to empty:|time to full:/ {print $2; exit}')
    energy_rate=$(echo "$info" | awk -F': +' '/energy-rate:|energy rate:|energy-rate|energy-rate/ {print $2; exit}')
    if [ -n "$energy_rate" ]; then
      power_w=$(echo "$energy_rate" | grep -oE '[0-9]+(\.[0-9]+)?' | head -n1 || true)
    fi
    if [ -n "$timetxt" ]; then
      if echo "$timetxt" | grep -q ':'; then
        IFS=: read -r hh mm ss <<< "$timetxt"
        tim=$(printf "%d:%02d" "$hh" "$mm")
      else
        if echo "$timetxt" | grep -qE 'hour'; then
          num=$(echo "$timetxt" | grep -oE '[0-9]+(\.[0-9]+)?' | head -n1)
          H=$(awk -v f="$num" 'BEGIN{printf "%d", int(f)}')
          M=$(awk -v f="$num" 'BEGIN{printf "%02d", int((f-int(f))*60)}')
          tim=$(printf "%d:%02d" "$H" "$M")
        else
          tim="$timetxt"
        fi
      fi
    fi
  fi
fi

# Try acpi if upower missing
if [ -z "$capacity" ] && command -v acpi >/dev/null 2>&1; then
  out=$(acpi -b 2>/dev/null || true)
  if [ -n "$out" ]; then
    status=$(echo "$out" | awk -F': ' '{print $2}' | awk -F', ' '{print $1}' | head -n1)
    capacity=$(echo "$out" | awk -F', ' '{print $2}' | tr -d '%' | awk '{print $1}' | head -n1)
    timefield=$(echo "$out" | grep -oE '[0-9]{1,2}:[0-9]{2}:[0-9]{2}' | head -n1 || true)
    if [ -n "$timefield" ]; then
      IFS=: read -r hh mm ss <<< "$timefield"
      tim=$(printf "%d:%02d" "$hh" "$mm")
    fi
  fi
fi

# Sysfs fallback for capacity/status/power
if [ -n "$BAT_SYSFS" ] && [ -d "$BAT_SYSFS" ]; then
  if [ -z "$capacity" ]; then
    if [ -f "$BAT_SYSFS/capacity" ]; then
      capacity=$(cat "$BAT_SYSFS/capacity" 2>/dev/null || echo "")
    fi
  fi
  if [ -f "$BAT_SYSFS/status" ]; then
    status=$(cat "$BAT_SYSFS/status" 2>/dev/null || echo "$status")
  fi
  # try power_now (likely in uW)
  if [ -f "$BAT_SYSFS/power_now" ]; then
    p=$(cat "$BAT_SYSFS/power_now" 2>/dev/null || echo "0")
    if [ -n "$p" ] && [ "$p" -ne 0 ] 2>/dev/null; then
      # assume microwatts if large
      if [ "$p" -gt 1000 ]; then
        power_w=$(awk -v v="$p" 'BEGIN{printf "%f", v/1000000}')
      else
        power_w="$p"
      fi
    fi
  elif [ -f "$BAT_SYSFS/current_now" ] && [ -f "$BAT_SYSFS/voltage_now" ]; then
    cur=$(cat "$BAT_SYSFS/current_now" 2>/dev/null || echo "0")
    volt=$(cat "$BAT_SYSFS/voltage_now" 2>/dev/null || echo "0")
    if [ -n "$cur" ] && [ -n "$volt" ] && [ "$cur" -ne 0 ] 2>/dev/null; then
      # current in uA, voltage in uV -> power in uW
      power_w=$(awk -v c="$cur" -v v="$volt" 'BEGIN{printf "%f", (c/1000000)*(v/1000000)}')
    fi
  fi
fi

# Normalize status lowercase
# detect AC adapter online state (prefer AC0 if present)
AC_ONLINE=0
for d in /sys/class/power_supply/*; do
  if [ -f "$d/online" ]; then
    val=$(cat "$d/online" 2>/dev/null || echo 0)
    if [ "$val" -eq 1 ] 2>/dev/null; then
      AC_ONLINE=1
      break
    fi
  fi
done
status_lc=$(echo "$status" | tr '[:upper:]' '[:lower:]')
# if AC is online, prefer charging status so icons reflect plugged-in state
if [ "$AC_ONLINE" -eq 1 ]; then
  status_lc="charging"
fi

# Choose icon based on capacity and status
cap_int=""
if [ -n "$capacity" ]; then
  if echo "$capacity" | grep -qE '^[0-9]+([.][0-9]+)?$'; then
    cap_int=$(awk -v c="$capacity" 'BEGIN{printf "%d", int(c)}')
  fi
fi

if [[ "$status_lc" == *"disch"* ]] || [[ "$status_lc" == *"discharging"* ]]; then
  # discharging: use default (discharging) icons
  if [ -n "$cap_int" ]; then
    idx=$((cap_int / 10))
    if [ "$idx" -ge 10 ]; then idx=9; fi
    icon="${DEFAULT_ICONS[$idx]}"
  else
    icon="$ICON_DISCHARGING"
  fi
elif [[ "$status_lc" == *"not charging"* ]] || [[ "$status_lc" == *"not-charging"* ]] || [[ "$status_lc" == *"pending-charge"* ]] || [[ "$status_lc" == *"pending charge"* ]]; then
  # plugged but not actively charging: show default icons
  if [ -n "$cap_int" ]; then
    idx=$((cap_int / 10))
    if [ "$idx" -ge 10 ]; then idx=9; fi
    icon="${DEFAULT_ICONS[$idx]}"
  else
    icon="$ICON_UNKNOWN"
  fi
elif [[ "$status_lc" == *"charging"* ]]; then
  # charging: use charging icons
  if [ -n "$cap_int" ]; then
    idx=$((cap_int / 10))
    if [ "$idx" -ge 10 ]; then idx=9; fi
    icon="${CHARGING_ICONS[$idx]}"
  else
    icon="$ICON_CHARGING"
  fi
else
  icon="$ICON_UNKNOWN"
fi

# Build text: only show time when discharging
if [[ "$status_lc" == *"disch"* ]] || [[ "$status_lc" == *"discharging"* ]]; then
  text="${tim} ${capacity}% ${icon}"
else
  text="${capacity}% ${icon}"
fi

# Build tooltip: only wattage with arrow
arrow=""
if [[ "$status_lc" == *"disch"* ]]; then
  arrow="↓"
elif [[ "$status_lc" == *"charg"* ]]; then
  arrow="↑"
fi

power_str=""
if [ -n "$power_w" ]; then
  power_str=$(awk -v v="$power_w" 'BEGIN{printf "%.1f", v}')
  tooltip="${arrow} ${power_str}W"
else
  tooltip="${arrow} --W"
fi

# Output JSON
printf '{"text":"%s","tooltip":"%s"}\n' "$(escape_json "$text")" "$(escape_json "$tooltip")"
exit 0
