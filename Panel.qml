import QtQuick
import QtQuick.Effects
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "emilsall.spotify-wallpaper"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool widgetEnabled: setting("enabled", "On") !== "Off"
  readonly property string cropMode: setting("cropMode", "fullscreen")
  readonly property bool showTrackInfo: setting("showTrackInfo", "On") !== "Off"
  readonly property bool resetOnClose: setting("resetOnClose", "On") !== "Off"
  readonly property bool blurEffect: setting("blurEffect", "Off") !== "Off"
  readonly property string targetMonitor: setting("targetMonitor", "auto")
  readonly property string barSection: setting("barSection", "left")
  property var monitorOptions: ["auto", "all"]
  property string placementError: ""

  // Background-service setup state lives on the host widget (it owns the
  // FileView/Process). Default to "installed" so the section never flashes
  // before hostWidget is injected.
  readonly property bool serviceInstalled: hostWidget ? hostWidget.serviceInstalled : true
  readonly property bool installing: hostWidget ? hostWidget.installing : false
  readonly property string installOutput: hostWidget ? hostWidget.installOutput : ""

  function runInstall() { if (hostWidget) hostWidget.runInstall() }

  function refreshMonitors() {
    if (!monitorProc.running) monitorProc.running = true
  }

  function moveToSection(section) {
    if (placementProc.running || section === root.barSection) return
    root.placementError = ""
    // Persist the selection while the widget is still in its current section,
    // then use Omarchy's dedicated move operation. `bar set --section` treats
    // the section as a source selector, so passing the destination there makes
    // it look for the widget in a section it has not reached yet.
    root.updateSetting("barSection", section)
    placementProc.command = ["omarchy", "bar", "move", root.moduleName,
                             "--section", section]
    placementProc.running = true
  }

  Process {
    id: placementProc
    stderr: StdioCollector { id: placementStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.placementError = String(placementStderr.text || "Could not move the widget.").trim()
    }
  }

  Process {
    id: monitorProc
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var options = ["auto", "all"]
        try {
          var monitors = JSON.parse(String(text || "[]"))
          for (var i = 0; i < monitors.length; i++) options.push(String(monitors[i].name))
        } catch (e) {}
        root.monitorOptions = options
      }
    }
  }

  readonly property var cropOptions: [
    { value: "fullscreen", label: "Fullscreen" },
    { value: "centered-75", label: "Centered 75%" },
    { value: "centered-native", label: "Native" }
  ]
  readonly property var sectionOptions: [
    { value: "left", label: "Left" },
    { value: "center", label: "Centre" },
    { value: "right", label: "Right" }
  ]

  function open() { refreshMonitors(); controller.show() }
  function close() { controller.hide() }
  function toggle() { opened ? close() : open() }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. Keep the
  // host widget in step so its own writes don't clobber this key from a
  // stale copy (same pattern as the clock panel's persistSettings).
  function updateSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function toggleEnabled() {
    root.updateSetting("enabled", root.widgetEnabled ? "Off" : "On")
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: panelColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: panelColumn
          width: panelFlick.width
          spacing: Style.space(14)

          // Exposed for the hero's trailingControl, whose `root` resolves to
          // PanelHero (not this Panel) — reach panel state via `header`.
          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight

            PanelHero {
              id: hero
              width: parent.width
              title: "Spotify Wallpaper"
              meta: root.widgetEnabled ? "ACTIVE" : "DISABLED"
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.widgetEnabled ? 1.0 : 0.5
              iconComponent: Component {
                Item {
                  width: Style.font.display * 1.2
                  height: width
                  layer.enabled: true
                  layer.smooth: true
                  layer.effect: MultiEffect {
                    source: heroIcon
                    colorization: 1.0
                    colorizationColor: root.foreground
                  }
                  Image {
                    id: heroIcon
                    anchors.fill: parent
                    source: Qt.resolvedUrl("disc-album.svg")
                    sourceSize.width: 64
                    sourceSize.height: 64
                    smooth: true
                    mipmap: true
                  }
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  checked: root.widgetEnabled
                  foreground: hero.foreground
                  accent: root.accent
                  onToggled: root.toggleEnabled()
                }
              }
            }
          }

          PanelSeparator {
            foreground: root.foreground
          }

          // Setup section — only visible until the background service exists.
          // The widget auto-runs install.sh once on load; this is the status
          // display and manual retry path.
          Column {
            visible: !root.serviceInstalled
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "SETUP REQUIRED"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              text: "The background service that watches Spotify playback is not installed yet."
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Button {
              width: parent.width
              text: root.installing ? "Installing service…" : "Install background service"
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              iconSize: Style.font.icon
              foreground: root.foreground
              accent: root.accent
              verticalPadding: Style.space(14)
              bordered: true
              selected: true
              enabled: !root.installing
              onClicked: root.runInstall()
            }

            Text {
              visible: root.installOutput !== ""
              width: parent.width
              text: root.installOutput
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            PanelSeparator {
              foreground: root.foreground
            }
          }

          PanelSectionHeader {
            text: "TARGET MONITOR"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ComboBox {
            width: parent.width
            model: root.monitorOptions
            currentIndex: Math.max(0, root.monitorOptions.indexOf(root.targetMonitor))
            onActivated: root.updateSetting("targetMonitor", String(currentText))
          }

          Text {
            width: parent.width
            text: root.targetMonitor === "auto"
              ? "Auto uses the focused monitor when the wallpaper is applied."
              : root.targetMonitor === "all"
                ? "Album art is shown on every connected monitor."
                : "Album art is limited to the " + root.targetMonitor + " output."
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            foreground: root.foreground
          }

          PanelSectionHeader {
            text: "CROP MODE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ButtonGroup {
            width: parent.width
            options: root.cropOptions
            value: root.cropMode
            foreground: root.foreground
            background: Color.popups.background
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.body
            focusable: false
            onChanged: root.updateSetting("cropMode", value)
          }

          PanelSeparator {
            foreground: root.foreground
          }

          Toggle {
            label: "Show track info"
            description: "Display artist, album, and track title on the wallpaper"
            checked: root.showTrackInfo
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            width: parent.width
            onClicked: root.updateSetting("showTrackInfo", checked ? "Off" : "On")
          }

          Toggle {
            label: "Blur effect"
            description: "Fullscreen: blur the album art. Centered: blurred backdrop behind the art"
            checked: root.blurEffect
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            width: parent.width
            onClicked: root.updateSetting("blurEffect", checked ? "Off" : "On")
          }

          Toggle {
            label: "Reset on close"
            description: "Remove album art and reveal the Omarchy wallpaper when playback stops"
            checked: root.resetOnClose
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            width: parent.width
            onClicked: root.updateSetting("resetOnClose", checked ? "Off" : "On")
          }

          PanelSeparator {
            foreground: root.foreground
          }

          PanelSectionHeader {
            text: "BAR PLACEMENT"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ButtonGroup {
            width: parent.width
            options: root.sectionOptions
            value: root.barSection
            foreground: root.foreground
            background: Color.popups.background
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.body
            focusable: false
            enabled: !placementProc.running
            onChanged: root.moveToSection(value)
          }

          Text {
            visible: root.placementError !== ""
            width: parent.width
            text: root.placementError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: "Choose which section of the Omarchy bar contains the icon."
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
