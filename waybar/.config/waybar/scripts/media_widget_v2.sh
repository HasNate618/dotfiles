#!/usr/bin/env bash
set -u

# Enhanced media widget: writes dynamic GTK menu with cover, metadata, controls, and progress bar.
# Outputs JSON for Waybar custom module.

WAYBAR_MENU="/home/nate/.config/waybar/media-menu.xml"
COVER_DIR="/tmp/waybar"
COVER_PATH="$COVER_DIR/cover.png"
ICON_NOTE="󰝚"

mkdir -p "$COVER_DIR"

xml_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  s="${s//\'/&apos;}"
  printf '%s' "$s"
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

player="$(pick_player || true)"
if [ -z "$player" ]; then
  printf '{"text":"%s","tooltip":"%s","class":"stopped"}\n' "$ICON_NOTE" "No active media player"
  exit 0
fi

# Gather metadata
status="$(playerctl -p "$player" status 2>/dev/null || echo "Stopped")"
title="$(playerctl -p "$player" metadata xesam:title 2>/dev/null || true)"
artist="$(playerctl -p "$player" metadata xesam:artist 2>/dev/null | head -n 1 || true)"
album="$(playerctl -p "$player" metadata xesam:album 2>/dev/null || true)"
art_url="$(playerctl -p "$player" metadata mpris:artUrl 2>/dev/null || true)"

# Cache cover
if [ -n "$art_url" ]; then
  prev_url="$(cat "$COVER_DIR/cover_url" 2>/dev/null || true)"
  if [ "$art_url" != "$prev_url" ]; then
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
    printf '%s' "$art_url" > "$COVER_DIR/cover_url"
  fi
fi

position_raw="$(playerctl -p "$player" position 2>/dev/null || echo "0")"
length_us="$(playerctl -p "$player" metadata mpris:length 2>/dev/null || echo "0")"

position_sec="$(awk -v p="$position_raw" 'BEGIN{printf "%d", p}')"
length_sec=0
if [[ "$length_us" =~ ^[0-9]+$ ]] && [ "$length_us" -gt 0 ]; then
  length_sec=$((length_us / 1000000))
fi

fraction=0.0
if [ "$length_sec" -gt 0 ]; then
  fraction=$(awk -v p="$position_sec" -v l="$length_sec" 'BEGIN{if(l<=0){print 0}else{v=p/l; if(v>1)v=1; if(v<0)v=0; printf "%.3f", v}}')
fi

# Build menu XML dynamically
escaped_title="$(xml_escape "${title:-}")"
escaped_artist="$(xml_escape "${artist:-}")"
escaped_album="$(xml_escape "${album:-}")"
escaped_cover_path="$(xml_escape "$COVER_PATH")"
frac="$fraction"

cat > "$WAYBAR_MENU.tmp" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <object class="GtkMenu" id="menu">
    <child>
      <object class="GtkMenuItem" id="info">
        <child>
          <object class="GtkBox" id="info-box">
            <property name="orientation">horizontal</property>
            <property name="spacing">8</property>
            <child>
              <object class="GtkImage" id="cover">
                <property name="file">${escaped_cover_path}</property>
                <property name="pixel-size">64</property>
              </object>
            </child>
            <child>
              <object class="GtkBox" id="meta-box">
                <property name="orientation">vertical</property>
                <property name="spacing">4</property>
                <child>
                  <object class="GtkLabel" id="title">
                    <property name="label">${escaped_title}</property>
                    <property name="xalign">0</property>
                  </object>
                </child>
                <child>
                  <object class="GtkLabel" id="artist">
                    <property name="label">${escaped_artist}</property>
                    <property name="xalign">0</property>
                  </object>
                </child>
                <child>
                  <object class="GtkBox" id="controls-row">
                    <property name="orientation">horizontal</property>
                    <property name="spacing">6</property>
                    <child>
                      <object class="GtkButton" id="prev">
                        <child>
                          <object class="GtkLabel"><property name="label">⏮</property></object>
                        </child>
                      </object>
                    </child>
                    <child>
                      <object class="GtkButton" id="playpause">
                        <child>
                          <object class="GtkLabel"><property name="label">⏯</property></object>
                        </child>
                      </object>
                    </child>
                    <child>
                      <object class="GtkButton" id="next">
                        <child>
                          <object class="GtkLabel"><property name="label">⏭</property></object>
                        </child>
                      </object>
                    </child>
                    <child>
                      <object class="GtkProgressBar" id="timeline">
                        <property name="fraction">${frac}</property>
                        <property name="hexpand">True</property>
                      </object>
                    </child>
                  </object>
                </child>
              </object>
            </child>
          </object>
        </child>
      </object>
    </child>
  </object>
</interface>
EOF

# Atomic move
mv "$WAYBAR_MENU.tmp" "$WAYBAR_MENU" 2>/dev/null || true

# Prepare Waybar JSON output
status_class="$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')"
if [ -z "$title" ]; then
  display_text="$ICON_NOTE"
else
  display_text="$ICON_NOTE"
fi

# Build tooltip
tooltip_text=""
if [ -n "$title" ]; then
  tooltip_text+="$title"
fi
if [ -n "$artist" ]; then
  tooltip_text+="\n$artist"
fi
if [ "$length_sec" -gt 0 ]; then
  tooltip_text+="\n$(printf '%d:%02d' $((position_sec/60)) $((position_sec%60))) / $(printf '%d:%02d' $((length_sec/60)) $((length_sec%60)))"
fi

# Output JSON line for Waybar
json_text="$(printf '%s' "$display_text" | sed 's/"/\\"/g')"
json_tooltip="$(printf '%s' "$tooltip_text" | sed 's/"/\\"/g')"
printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$json_text" "$json_tooltip" "$status_class"
exit 0
