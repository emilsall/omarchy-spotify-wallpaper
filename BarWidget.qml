import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "emilsall.spotify-wallpaper"

  readonly property string iconSource: Qt.resolvedUrl("disc-album.svg")

  readonly property bool enabled: setting("enabled", "On") !== "Off"
  readonly property string cropMode: setting("cropMode", "fullscreen")
  readonly property bool showTrackInfo: setting("showTrackInfo", "On") !== "Off"
  readonly property bool resetOnClose: setting("resetOnClose", "On") !== "Off"
  readonly property bool blurEffect: setting("blurEffect", "Off") !== "Off"

  // --- Background service setup (self-install) ---
  readonly property string serviceName: "omarchy-spotify-wallpaper.service"
  property bool serviceInstalled: false
  property bool installing: false
  property string installOutput: ""
  property string depsMissing: ""
  property bool setupChecked: false

  function pluginFile(name) {
    return decodeURIComponent(Qt.resolvedUrl(name).toString().replace(/^file:\/\//, ""))
  }

  function runInstall() {
    if (installProc.running) return
    root.installing = true
    root.installOutput = ""
    // --install-deps routes missing packages through pkexec (polkit prompt).
    installProc.command = ["/usr/bin/bash", pluginFile("install.sh"), "--install-deps"]
    installProc.running = true
  }

  FileView {
    id: serviceFile
    path: Quickshell.env("HOME") + "/.config/systemd/user/" + root.serviceName
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.serviceInstalled = true
      root.setupChecked = true
    }
    onLoadFailed: {
      root.serviceInstalled = false
      // Auto-install only on the initial check (widget load). A later failure
      // means the unit was removed deliberately (uninstall.sh) — show the
      // setup section in the panel, but don't fight the user by reinstalling.
      if (!root.setupChecked) {
        root.setupChecked = true
        Qt.callLater(root.runInstall)
      }
    }
    onFileChanged: reload()
  }

  Process {
    id: installProc
    stdout: StdioCollector { id: installStdout; waitForEnd: true }
    stderr: StdioCollector { id: installStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.installing = false
      if (exitCode === 0) {
        root.installOutput = ""
        root.depsMissing = ""
      } else {
        var out = (installStdout.text + "\n" + installStderr.text).trim()
        root.installOutput = out
        // install.sh prints "Missing dependencies: <cmds>" on stderr (exit 2)
        // when deps are absent and it was not told to install them. Surface
        // that list so the panel can offer a password-prompted install button.
        var m = /Missing dependencies:\s*(.+)/.exec(out)
        root.depsMissing = m ? String(m[1]).trim() : ""
      }
    }
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  onBarChanged: Qt.callLater(injectPanel)
  onSettingsChanged: Qt.callLater(injectPanel)
  Component.onCompleted: Qt.callLater(injectPanel)

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    fixedWidth: Style.bar.iconSlot
    hasVisualContent: true
    dimmed: !root.enabled
    keepSpace: true
    tooltipText: !root.serviceInstalled
      ? (root.depsMissing !== ""
         ? "Spotify Wallpaper \u00B7 Dependencies required"
         : "Spotify Wallpaper \u00B7 Setup required")
      : root.enabled ? "Spotify Wallpaper \u00B7 " + root.cropMode : "Spotify Wallpaper \u00B7 Disabled"

    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
      else if (b === Qt.RightButton) {
        var newVal = root.enabled ? "Off" : "On"
        var entry = { id: root.moduleName }
        for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
        entry["enabled"] = newVal
        root.settings = entry
        if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
          root.bar.shell.updateEntryInline(root.moduleName, entry)
      }
    }

    Item {
      anchors.centerIn: parent
      width: Style.bar.iconSlot * 0.9
      height: width
      opacity: root.enabled ? 1.0 : 0.45
      layer.enabled: true
      layer.smooth: true
      layer.effect: MultiEffect {
        source: iconImage
        colorization: 1.0
        colorizationColor: button.foreground
      }

      Image {
        id: iconImage
        anchors.fill: parent
        source: root.iconSource
        sourceSize.width: 64
        sourceSize.height: 64
        smooth: true
        mipmap: true
      }
    }
  }
}
