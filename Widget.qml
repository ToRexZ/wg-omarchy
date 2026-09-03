import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "wg-omarchy"
  // Panel gates its IpcHandler on ipcTarget, not moduleName, so without this
  // the panel cannot be opened from a keybind or `omarchy-shell ipc`.
  ipcTarget: "wg-omarchy"

  // NetworkManager owns this tunnel, so up/down is a connection action rather
  // than `wg-quick`: there is no /etc/wireguard/<iface>.conf to read and no
  // root to acquire. polkit's network-control grant covers the active session.
  // setting() is Panel's reader for this widget's shell.json entry and handles
  // an explicit null, which a plain `settings.connection` check does not.
  readonly property string connName: setting("connection", "wg0")

  // The shell's palette is five roles — foreground, background, accent, urgent,
  // muted — and green is not one of them. `Color.loadColors()` matches the
  // theme's `green` key and drops it, so the one value this widget wants is the
  // one value the singleton will not hand over: read it from the theme file.
  //
  // Empty until the read lands (and for a hand-written theme that omits the
  // key), so the fallback is a muted green that survives a light theme too.
  property string themeGreen: ""
  readonly property color upColor: themeGreen !== "" ? themeGreen : "#a3be8c"
  readonly property color downColor: Color.muted

  property bool vpnOn: false
  property bool busy: false
  property string errorText: ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: statusProbe.running = true

  Timer {
    id: poll
    interval: 5000
    repeat: true
    running: true
    onTriggered: if (!root.busy) statusProbe.running = true
  }

  // Scoped to one connection on purpose. The old `ip link | grep tun|tap|wg|ppp`
  // probe reported ON for any tunnel on the box — a devcontainer veth or a
  // second VPN would light this widget up for a tunnel it cannot toggle.
  // GENERAL.STATE is absent entirely until the connection is activated, so
  // empty output means down.
  Process {
    id: statusProbe
    running: false
    command: ["nmcli", "-t", "-f", "GENERAL.STATE", "con", "show", "id", root.connName]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.vpnOn = String(text).indexOf("activated") >= 0
    }
  }

  Process {
    id: toggleProc
    running: false
    onExited: function(code, status) {
      root.busy = false
      root.errorText = (code === 0) ? "" : "Failed"
      refreshTimer.start()
    }
  }

  Timer {
    id: refreshTimer
    interval: 1500
    repeat: false
    onTriggered: statusProbe.running = true
  }

  // Same key/value shape the shell's own parser accepts, so a quoted or bare
  // hex reads identically here and there.
  function readThemeGreen(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*green\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (m) {
        root.themeGreen = m[1]
        return
      }
    }
    root.themeGreen = ""
  }

  FileView {
    id: themeColors
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.readThemeGreen(text())
    // `text()` is stale inside the change signal, so both paths go through
    // reload → onLoaded to always parse fresh content. Same reason
    // Color.userShellFile does it this way.
    onFileChanged: reload()
    onLoadFailed: root.themeGreen = ""
  }

  // A runtime theme switch never touches the path above: omarchy repoints the
  // `current/theme` symlink and pushes the new payload to the shell over IPC,
  // which is why Color's own colorsFile sets watchChanges false and calls this
  // a startup load. That push always reassigns Color's roles, so their change
  // signals are the notification this widget gets. Three of them, because two
  // themes can agree on any one value.
  Connections {
    target: Color
    function onBackgroundChanged() { themeColors.reload() }
    function onForegroundChanged() { themeColors.reload() }
    function onAccentChanged() { themeColors.reload() }
  }

  function submitAction() {
    if (root.busy || toggleProc.running) return
    root.busy = true
    root.errorText = ""
    // --wait bounds a handshake that never completes; without it nmcli blocks
    // for its 90s default and the widget sits on "…" the whole time.
    toggleProc.command = root.vpnOn
      ? ["nmcli", "con", "down", "id", root.connName]
      : ["nmcli", "--wait", "15", "con", "up", "id", root.connName]
    toggleProc.running = true
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌆"
    active: root.vpnOn
    // Left to itself this glyph is `bar.active` when up — which falls back to
    // `urgent`, the same red the widget uses for Disconnect — and the bar
    // foreground at 45% opacity when down, i.e. a faded copy of the up colour
    // rather than a colour of its own. Both are named here instead, and
    // `dimmed` is gone with them: down is a full-strength grey, not a ghost.
    activeColor: root.upColor
    foreground: root.downColor
    tooltipText: root.connName + (root.vpnOn ? ": ON" : ": OFF")
    onPressed: function(b) {
      statusProbe.running = true
      root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(14)

      Item {
        id: header
        width: parent.width
        implicitHeight: headerRow.implicitHeight

        Row {
          id: headerRow
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(12)

          Text {
            id: keyIcon
            anchors.verticalCenter: parent.verticalCenter
            text: "󰷖"
            color: root.barForeground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
          }

          Text {
            id: title
            anchors.verticalCenter: parent.verticalCenter
            text: root.connName
            color: root.barForeground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.heading
          }
        }
      }

      Item {
        width: parent.width
        implicitHeight: statusRow.implicitHeight

        Row {
          id: statusRow
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          Text {
            text: "Status"
            color: root.barForeground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            text: root.vpnOn ? "ON" : "OFF"
            color: root.vpnOn ? Color.accent : root.barForeground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }

      Button {
        width: parent.width
        text: root.busy ? "…" : (root.errorText !== "" ? root.errorText : (root.vpnOn ? "Disconnect" : "Connect"))
        accent: (root.vpnOn || root.errorText !== "") ? Color.urgent : Color.accent
        bordered: true
        onClicked: root.submitAction()
      }
    }
  }
}
