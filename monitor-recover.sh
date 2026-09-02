#!/usr/bin/env bash
# Re-apply native 4K to external monitors after wake from sleep.
#
# After s2idle resume the USB-C dock's DisplayPort link retrains at reduced
# bandwidth, so Hyprland's 3840x2160@60 rule gets rejected and the panel falls
# back to a low mode (e.g. 2560x1440). This script polls the link with backoff,
# applies the best available 4K mode each round (@60 as soon as it comes back),
# and never touches the internal panel (clamshell logic owns that).
#
# Exit codes:
#   0  all external monitors reached native 4K
#   1  no Hyprland instance, or timed out waiting for full-speed link

set -u

readonly TARGET_RES="3840x2160"
readonly TARGET_W="${TARGET_RES%%x*}"
readonly TARGET_H="${TARGET_RES##*x}"
readonly MIN_REFRESH_OK=55
readonly TIMEOUT="${TIMEOUT:-180}"

# Resolve the running Hyprland instance.
sig="$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -n 1)"
if [[ -z "$sig" ]]; then
  echo "no running Hyprland instance" >&2
  exit 1
fi
readonly SIG="$sig"

monitors_json() {
  HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl monitors all -j 2>/dev/null
}

# Names of external outputs currently known to Hyprland (enabled or not).
external_names() {
  monitors_json | jq -r '.[] | select(.name != "eDP-1") | .name'
}

# Tab-separated fields of one output: x y scale refresh width height
monitor_fields() {
  monitors_json | jq -r --arg m "$1" \
    '.[] | select(.name == $m)
     | [(.x|tostring), (.y|tostring), (.scale|tostring),
        (.refreshRate|round|tostring), (.width|tostring), (.height|tostring)]
     | join("\t")'
}

# The 4K modes the EDID currently advertises, highest refresh first.
target_candidates() {
  monitors_json | jq -r \
    '.[] | .availableModes[]? | select(startswith("3840x2160@")) | sub("Hz$";"")' \
    | sort -t@ -k2,2gr | uniq
}

apply_mode() {
  local name="$1" mode="$2" fields x y scale
  fields="$(monitor_fields "$name")"
  IFS=$'\t' read -r x y scale _ <<<"$fields"
  [[ -n "${x:-}" ]] || return 1

  local hl_string
  hl_string=$(printf 'hl.monitor({ output = "%s", mode = "%s", position = "%sx%s", scale = %s })' \
    "$name" "$mode" "$x" "$y" "$scale")
  HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl eval "$hl_string" >/dev/null 2>&1
}

all_done() {
  local name fields refresh width height
  while IFS= read -r name; do
    fields="$(monitor_fields "$name")"
    IFS=$'\t' read -r _ _ _ refresh width height <<<"$fields"
    if [[ "$width" == "$TARGET_W" && "$height" == "$TARGET_H" &&
          "${refresh:-0}" -ge "$MIN_REFRESH_OK" ]]; then
      continue
    fi
    return 1
  done < <(external_names)
  return 0
}

deadline=$(( $(date +%s) + TIMEOUT ))

while :; do
  if all_done; then
    echo "all external monitors at native 4K"
    exit 0
  fi

  progress=0
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue

    mapfile -t candidates < <(target_candidates)
    (( ${#candidates[@]} > 0 )) || continue  # panel doesn't do our target res

    # Try modes from fastest down; keep the first the link actually accepts.
    for cand in "${candidates[@]}"; do
      cand_refresh="${cand##*@}"
      cand_int="${cand_refresh%%.*}"

      fields="$(monitor_fields "$name")"
      IFS=$'\t' read -r _ _ _ cur_refresh width height <<<"$fields"

      if [[ "$width" == "$TARGET_W" && "$height" == "$TARGET_H" &&
            "${cur_refresh:-0}" -ge "$MIN_REFRESH_OK" ]]; then
        break  # already at full-speed 4K
      fi

      apply_mode "$name" "$cand"
      sleep 1

      fields="$(monitor_fields "$name")"
      IFS=$'\t' read -r _ _ _ new_refresh new_w new_h <<<"$fields"
      if [[ "$new_w" == "$TARGET_W" && "$new_h" == "$TARGET_H" &&
            "${new_refresh:-0}" -ge "$cand_int" ]]; then
        echo "$name: now at ${new_w}x${new_h}@${new_refresh} (wanted $cand)"
        progress=1
        break
      fi
    done
  done < <(external_names)

  (( progress )) && sleep 3 || sleep 8

  (( $(date +%s) < deadline )) || break
done

if all_done; then
  echo "all external monitors at native 4K (late)"
  exit 0
fi
echo "gave up waiting for full-speed link; leaving best-effort modes in place"
exit 1
