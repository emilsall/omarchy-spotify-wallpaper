import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Item {
  id: root

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/spotify-wallpaper"
  readonly property string stateFile: stateDir + "/active-wallpaper.json"
  property string wallpaperPath: ""
  property string targetMonitor: ""

  function loadState() {
    if (!stateReader.running) stateReader.running = true
  }

  Process {
    id: stateDirSetup
    command: ["mkdir", "-p", root.stateDir]
    onExited: {
      stateWatcher.reload()
      root.loadState()
    }
  }

  Process {
    id: stateReader
    command: ["bash", "-c", "[[ -f \"$1\" ]] && cat -- \"$1\"", "spotify-wallpaper-state", root.stateFile]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.wallpaperPath = ""
          root.targetMonitor = ""
          return
        }
        try {
          var state = JSON.parse(raw)
          root.wallpaperPath = String(state.path || "")
          root.targetMonitor = String(state.monitor || "")
        } catch (e) {
          root.wallpaperPath = ""
          root.targetMonitor = ""
        }
      }
    }
  }

  FileView {
    id: stateWatcher
    path: root.stateDir
    watchChanges: true
    printErrors: false
    onFileChanged: root.loadState()
    onLoaded: root.loadState()
  }

  Component.onCompleted: stateDirSetup.running = true

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.wallpaperPath !== "" &&
               (root.targetMonitor === "all" || root.targetMonitor === String(modelData.name || ""))
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }

      WlrLayershell.namespace: "omarchy-spotify-wallpaper"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Image {
        anchors.fill: parent
        source: root.wallpaperPath
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
      }
    }
  }
}
