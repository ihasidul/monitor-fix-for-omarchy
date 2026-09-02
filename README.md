# Monitor Recover

An Omarchy bar widget that re-applies native 4K resolution to external monitors after wake from sleep.

## Why

After s2idle resume, the USB-C dock's DisplayPort link retrains at reduced bandwidth, so Hyprland's 3840x2160@60 rule gets rejected and the panel falls back to a low mode (e.g. 2560x1440). This plugin polls the link with backoff, applies the best available 4K mode each round (@60 as soon as it comes back), and never touches the internal panel.

## Install

```sh
omarchy plugin add https://github.com/ihasidul/monitor-fix-for-omarchy.git --enable
```

Or manually:

```sh
PLUGIN_ID="hasidul.monitor-recover"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
mkdir -p "$PLUGIN_DIR"
# copy files into $PLUGIN_DIR
omarchy-shell shell rescanPlugins
omarchy plugin enable "$PLUGIN_ID"
```

## Usage

Click the monitor icon (󰍹) in the bar to trigger recovery. The icon changes to indicate status:

- **󰍹** — idle, ready to recover
- **󰦕** — recovery in progress
- **󰄬** — recovery succeeded
- **󰄮** — recovery failed or timed out

The recovery process runs with a 180-second timeout, polling every few seconds and trying the highest refresh 4K mode available.

## Structure

- `BarWidget.qml` — the bar widget UI and status handling
- `monitor-recover.sh` — the standalone recovery script, also runnable directly:

  ```sh
  ~/.config/omarchy/plugins/hasidul.monitor-recover/monitor-recover.sh
  ```

  Exit codes: `0` when all external monitors reach native 4K, `1` when no
  Hyprland instance exists or the full-speed link never appears within the
  timeout.

## Configuration

Add to your `~/.config/omarchy/shell.json` bar layout:

```json
{
  "bar": {
    "layout": {
      "right": [
        { "id": "hasidul.monitor-recover" }
      ]
    }
  }
}
```

## Remove

```sh
omarchy plugin remove hasidul.monitor-recover
```
