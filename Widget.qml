import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "wg-omarchy"

  property bool vpnOn: false
  property bool showingPrompt: false
  property string passwordText: ""
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
    onTriggered: statusProbe.running = true
  }

  // ponytail: any tunnel interface counts as "on"; refine per-interface if a specific VPN type matters.
  Process {
    id: statusProbe
    running: false
    command: ["sh", "-c", "ip link show | grep -E 'tun|tap|wg|ppp'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.vpnOn = String(text).trim().length > 0
    }
  }

  // Runs `sudo wg-quick <up|down> wg0` with the password over stdin, never argv.
  Process {
    id: sudoProc
    property string secret: ""
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
    }
    onExited: function(code, status) {
      root.passwordText = ""
      root.busy = false
      if (code === 0) {
        root.errorText = ""
        root.showingPrompt = false
        refreshTimer.start()
      } else {
        root.beginAction()
        root.errorText = "Error"
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: 1500
    repeat: false
    onTriggered: statusProbe.running = true
  }

  function beginAction() {
    root.errorText = ""
    root.showingPrompt = true
    Qt.callLater(function() { if (root.showingPrompt) pwField.forceActiveFocus() })
  }

  function submitAction() {
    if (root.busy || sudoProc.running) return
    if (root.passwordText.length === 0) return
    var action = root.vpnOn ? "down" : "up"
    root.busy = true
    root.showingPrompt = false
    sudoProc.secret = root.passwordText
    root.passwordText = ""
    // sh reads the one line, printf closes the pipe, so sudo gets EOF and exits on a wrong password.
    sudoProc.command = ["sh", "-c", "read -r p && printf '%s\\n' \"$p\" | sudo -S wg-quick " + action + " wg0"]
    sudoProc.running = true
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌆"
    active: root.vpnOn
    dimmed: !root.vpnOn
    tooltipText: root.vpnOn ? "VPN: ON" : "VPN: OFF"
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
            text: "VPN"
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
        text: root.busy ? "…" : (root.errorText !== "" ? root.errorText : (root.vpnOn ? "OFF" : "ON"))
        accent: (root.vpnOn || root.errorText !== "") ? Color.urgent : Color.accent
        bordered: true
        onClicked: {
          if (root.showingPrompt) {
            root.showingPrompt = false
            root.passwordText = ""
          } else root.beginAction()
        }
      }

      TextField {
        id: pwField
        width: parent.width
        visible: root.showingPrompt
        password: true
        placeholderText: "Sudo password"
        text: root.showingPrompt ? root.passwordText : ""
        onTextChanged: if (root.showingPrompt && text !== root.passwordText) root.passwordText = text
        onAccepted: root.submitAction()
      }
    }
  }
}
