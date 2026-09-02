import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "ami.monitor-recover"

  property bool running: false
  property bool succeeded: false
  property bool failed: false

  function runRecovery() {
    if (running) return
    running = true
    succeeded = false
    failed = false
    recoverProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Timer {
    id: resetTimer
    interval: 3000
    repeat: false
    onTriggered: {
      root.succeeded = false
      root.failed = false
    }
  }

  Process {
    id: recoverProc
    command: ["bash", "-c", `
set -u
TARGET_RES="3840x2160"
TW=\${TARGET_RES%x*}
TH=\${TARGET_RES#*x}
MIN_REFRESH_OK=55
TIMEOUT="\${TIMEOUT:-180}"

sig=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -n1)
if [[ -z $sig ]]; then
    echo "no running Hyprland instance"
    exit 1
fi
export HYPRLAND_INSTANCE_SIGNATURE="$sig"

monitors_json() {
    HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl monitors all -j 2>/dev/null
}

external_names() {
    monitors_json | jq -r '.[] | select(.name != "eDP-1") | .name'
}

monitor_fields() {
    monitors_json | jq -r --arg m "$1" \
        '.[] | select(.name == $m) | [(.x|tostring), (.y|tostring), (.scale|tostring), (.refreshRate|round|tostring), (.width|tostring), (.height|tostring)] | join("\\t")'
}

target_candidates() {
    monitors_json | jq -r '.[] | .availableModes[]? | select(startswith("3840x2160@")) | sub("Hz$";"")' \
        | sort -t@ -k2,2gr | uniq
}

apply_mode() {
    local name=$1 mode=$2 fields x y scale
    fields=$(monitor_fields "$name")
    IFS=$'\\t' read -r x y scale _rest <<<"$fields"
    [[ -n \${x:-} ]] || return 1
    hl_string=$(printf 'hl.monitor({ output = "%s", mode = "%s", position = "%sx%s", scale = %s })' \
        "$name" "$mode" "$x" "$y" "$scale")
    HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl eval "$hl_string" >/dev/null 2>&1
}

all_done() {
    local name fields refresh width height
    while IFS= read -r name; do
        fields=$(monitor_fields "$name")
        IFS=$'\\t' read -r _x _y _scale refresh width height <<<"$fields"
        if [[ $width == "$TW" && $height == "$TH" && \${refresh:-0} -ge $MIN_REFRESH_OK ]]; then
            continue
        fi
        return 1
    done < <(external_names)
    return 0
}

deadline=$(( $(date +%s) + TIMEOUT ))

while :; do
    if all_done; then
        exit 0
    fi

    progress=0
    while IFS= read -r name; do
        [[ -n $name ]] || continue
        mapfile -t cands < <(target_candidates)
        (( \${#cands[@]} > 0 )) || continue
        for cand in "\${cands[@]}"; do
            cref=\${cand##*@}
            cref_int=\${cref%%.*}
            fields=$(monitor_fields "$name")
            IFS=$'\\t' read -r _x _y _scale cur_refresh width height <<<"$fields"
            if [[ $width == "$TW" && $height == "$TH" && \${cur_refresh:-0} -ge $MIN_REFRESH_OK ]]; then
                break
            fi
            apply_mode "$name" "$cand"
            sleep 1
            fields=$(monitor_fields "$name")
            IFS=$'\\t' read -r _x _y _scale new_refresh new_w new_h <<<"$fields"
            if [[ $new_w == "$TW" && $new_h == "$TH" && \${new_refresh:-0} -ge $cref_int ]]; then
                progress=1
                break
            fi
        done
    done < <(external_names)

    (( progress )) && sleep 3 || sleep 8
    now=$(date +%s)
    (( now < deadline )) || break
done

if all_done; then
    exit 0
fi
exit 1
`]
    onRunningChanged: {
      if (!running) {
        root.running = false
        if (recoverProc.exitCode === 0) {
          root.succeeded = true
          resetTimer.restart()
        } else {
          root.failed = true
          resetTimer.restart()
        }
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: {
      if (root.running) return "󰦕"
      if (root.succeeded) return "󰄬"
      if (root.failed) return "󰄮"
      return "󰍹"
    }
    tooltipText: root.running ? "Recovering monitors..." : "Recover 4K monitors"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.runRecovery()
    }
  }
}
