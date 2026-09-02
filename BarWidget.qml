import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// A bar widget that triggers 4K monitor recovery on external displays.
//
// After wake-from-sleep, USB-C docks often retrain their DisplayPort link at
// reduced bandwidth, causing Hyprland to fall back to a low resolution. Click
// the icon to run the recovery script, which polls the link with backoff until
// it returns to native 3840x2160 or the timeout elapses.
BarWidget {
  id: root
  moduleName: "ami.monitor-recover"

  readonly property int statusIdle: 0
  readonly property int statusRunning: 1
  readonly property int statusSuccess: 2
  readonly property int statusFailed: 3

  property int status: statusIdle
  readonly property bool running: status === statusRunning

  readonly property string icon: {
    if (status === statusRunning) return "󰦕"
    if (status === statusSuccess) return "󰄬"
    if (status === statusFailed)  return "󰄮"
    return "󰍹"
  }

  readonly property string tooltip: {
    if (status === statusRunning) return "Recovering monitors..."
    if (status === statusSuccess) return "Monitors recovered"
    if (status === statusFailed)  return "Monitor recovery failed"
    return "Recover 4K monitors"
  }

  // Filesystem directory of this QML file, used to resolve the sibling
  // recovery script. Hot-reloaded plugins keep the file available on disk, so
  // the directory always resolves.
  readonly property string baseDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")

  function startRecovery() {
    if (running) return
    status = statusRunning
    recoverProc.running = true
  }

  // Clear transient success/failure feedback after a short pause.
  Timer {
    id: resetTimer
    interval: 3000
    repeat: false
    onTriggered: {
      if (!recoverProc.running)
        root.status = root.statusIdle
    }
  }

  // The recovery logic lives in monitor-recover.sh (next to this file),
  // keeping the shell script separate and testable outside Quickshell.
  Process {
    id: recoverProc
    command: ["bash", root.baseDir + "/monitor-recover.sh"]

    onRunningChanged: {
      if (running) return
      root.status = recoverProc.exitCode === 0
        ? root.statusSuccess
        : root.statusFailed
      resetTimer.restart()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    tooltipText: root.tooltip
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.startRecovery()
    }
  }
}
