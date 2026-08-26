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

  // Crossfade state shared by every screen's layer, mirroring the shell's
  // 420 ms background reveal: a new art path fades in over the previous one,
  // and an empty path fades the art out before the layer hides.
  property string displayPath: ""
  property string fadeFromPath: ""
  property string activeMonitor: ""
  property real artOpacity: 0

  onWallpaperPathChanged: {
    if (root.wallpaperPath !== "") {
      if (root.displayPath !== "" && root.displayPath !== root.wallpaperPath)
        root.fadeFromPath = root.displayPath
      root.displayPath = root.wallpaperPath
      root.activeMonitor = root.targetMonitor
      fadeOutClearTimer.stop()
      revealAnim.restart()
    } else if (root.displayPath !== "") {
      hideAnim.restart()
    }
  }

  NumberAnimation {
    id: revealAnim
    target: root
    property: "artOpacity"
    from: 0
    to: 1
    duration: 420
    easing.type: Easing.InOutCubic
    onFinished: root.fadeFromPath = ""
  }

  NumberAnimation {
    id: hideAnim
    target: root
    property: "artOpacity"
    to: 0
    duration: 420
    easing.type: Easing.InOutCubic
    onFinished: {
      root.displayPath = ""
      root.fadeFromPath = ""
      root.activeMonitor = ""
    }
  }

  Timer {
    id: fadeOutClearTimer
    interval: 500
    onTriggered: root.fadeFromPath = ""
  }

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
          root.targetMonitor = ""
          root.wallpaperPath = ""
          return
        }
        try {
          var state = JSON.parse(raw)
          // targetMonitor first: the wallpaperPath handler snapshots it.
          root.targetMonitor = String(state.monitor || "")
          root.wallpaperPath = String(state.path || "")
        } catch (e) {
          root.targetMonitor = ""
          root.wallpaperPath = ""
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
      visible: root.displayPath !== "" &&
               (root.activeMonitor === "all" || root.activeMonitor === String(modelData.name || ""))
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }

      WlrLayershell.namespace: "omarchy-spotify-wallpaper"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      // Previous art stays fully opaque underneath while the new art fades in.
      Image {
        anchors.fill: parent
        source: root.fadeFromPath
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        visible: root.fadeFromPath !== "" && root.artOpacity < 1
      }

      Image {
        anchors.fill: parent
        source: root.displayPath
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        visible: root.displayPath !== ""
        opacity: root.artOpacity
      }
    }
  }
}
