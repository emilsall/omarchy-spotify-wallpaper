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
  // 420 ms background reveal. Two image slots ping-pong: each new art path is
  // loaded into the covered slot while the current art stays fully opaque on
  // top, and the fade only starts once the load finished — so a track change
  // never flashes the theme wallpaper through a half-loaded image.
  property string pathA: ""          // source of slot A
  property string pathB: ""          // source of slot B
  property bool aOnTop: true         // which slot is the newest (top) one
  property string displayPath: ""    // art the top slot holds
  property string incomingPath: ""   // art currently loading/fading in
  property string activeMonitor: ""
  property real fadeOpacity: 0
  property bool hiding: false

  onWallpaperPathChanged: {
    var path = root.wallpaperPath
    if (path !== "") {
      if (path === root.displayPath || path === root.incomingPath) return
      // A fade still in flight snaps to its target before the next one starts.
      if (root.incomingPath !== "") {
        root.displayPath = root.incomingPath
        root.fadeOpacity = 1
        revealAnim.stop()
      }
      root.incomingPath = path
      root.activeMonitor = root.targetMonitor
      root.hiding = false
      // Load into the covered slot; the current art stays opaque above it.
      if (root.pathA !== root.displayPath || root.displayPath === "") {
        root.pathA = path
        root.aOnTop = true
      } else {
        root.pathB = path
        root.aOnTop = false
      }
      // The incoming slot starts fully transparent while it decodes.
      root.fadeOpacity = 0
    } else if (root.displayPath !== "" && !root.hiding) {
      root.hiding = true
      hideAnim.restart()
    }
  }

  NumberAnimation {
    id: revealAnim
    target: root
    property: "fadeOpacity"
    from: 0
    to: 1
    duration: 420
    easing.type: Easing.InOutCubic
    onFinished: {
      root.displayPath = root.incomingPath
      root.incomingPath = ""
    }
  }

  NumberAnimation {
    id: hideAnim
    target: root
    property: "fadeOpacity"
    to: 0
    duration: 420
    easing.type: Easing.InOutCubic
    onFinished: {
      root.displayPath = ""
      root.incomingPath = ""
      root.pathA = ""
      root.pathB = ""
      root.activeMonitor = ""
      root.hiding = false
      root.fadeOpacity = 0
    }
  }

  function maybeReveal(img, path) {
    if (img.status !== Image.Ready) return
    if (root.incomingPath === "" || path !== root.incomingPath) return
    if (root.hiding || revealAnim.running) return
    revealAnim.restart()
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
      visible: root.displayPath !== "" || root.incomingPath !== ""
               ? (root.activeMonitor === "all" || root.activeMonitor === String(modelData.name || ""))
               : false
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      WlrLayershell.namespace: "omarchy-spotify-wallpaper"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Image {
        id: imgOver
        anchors.fill: parent
        source: root.pathA
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        visible: root.pathA !== ""
        z: root.aOnTop ? 1 : 0
        opacity: root.pathA === root.displayPath && root.displayPath !== "" && !root.hiding ? 1 : root.fadeOpacity
      }

      Image {
        id: imgUnder
        anchors.fill: parent
        source: root.pathB
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        visible: root.pathB !== ""
        z: root.aOnTop ? 0 : 1
        opacity: root.pathB === root.displayPath && root.displayPath !== "" && !root.hiding ? 1 : root.fadeOpacity
      }
    }
  }
}
