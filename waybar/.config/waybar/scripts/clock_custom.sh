#!/usr/bin/env bash
set -u

escape_json() {
  # escape backslashes and double quotes
  printf "%s" "$1" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\"/g'
}

# Use GNU date to remove leading zero from hour (%-I)
text="$(date '+%-I:%M %p — %d %b %Y')"
tooltip="$(date '+%A, %d %B %Y %I:%M %p')"

printf '{"text":"%s","tooltip":"%s"}\n' "$(escape_json "$text")" "$(escape_json "$tooltip")"
