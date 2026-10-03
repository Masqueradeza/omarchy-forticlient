import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "marcd.forticlient"
  ipcTarget: "marcd.forticlient"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string statusText: {
    if (!service.checkedInstalled) return "Checking…"
    if (!service.installed) return "FortiClient is not installed"
    if (service.profile === "") return "No VPN profile configured"
    if (service.vpnState === "connected") return "Connected"
    if (service.vpnState === "connecting") return "Connecting…"
    if (service.vpnState === "disconnecting") return "Disconnecting…"
    if (service.vpnState === "failed") return "Connection failed"
    return "Disconnected"
  }

  readonly property string tooltip: {
    if (!service.connected) return "FortiClient VPN · " + statusText
    var parts = [service.profile]
    if (service.info.ip !== "") parts.push(service.info.ip)
    if (service.info.duration !== "") parts.push(service.info.duration)
    return "FortiClient VPN · " + parts.join(" · ")
  }

  readonly property string hintCommand: Model.terminalConnectCommand(service.profile, service.hint === "needsPassword")

  readonly property color barIconColor: {
    if (service.vpnState === "failed") return root.urgent
    return service.connected ? barForeground : Qt.darker(barForeground, 1.55)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (!opened) return
    service.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: service
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function up(): string { service.connectVpn(); return "ok" }
    function down(): string { service.disconnectVpn(); return "ok" }
    function status(): string { return service.vpnState }
    function ip(): string { return service.info.ip }
  }

  component DetailRow: Item {
    id: detail
    property string label: ""
    property string value: ""
    property bool copyable: false

    width: parent ? parent.width : 0
    implicitHeight: Math.max(labelText.implicitHeight, copyButton.visible ? copyButton.implicitHeight : 0) + Style.space(4)

    Text {
      id: labelText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: detail.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      anchors.left: labelText.right
      anchors.leftMargin: Style.space(12)
      anchors.right: copyButton.visible ? copyButton.left : parent.right
      anchors.rightMargin: copyButton.visible ? Style.space(6) : 0
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: detail.value !== "" ? detail.value : "—"
      elide: Text.ElideLeft
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    PanelActionButton {
      id: copyButton
      visible: detail.copyable && detail.value !== ""
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰆏"
      tooltipText: "Copy " + detail.label.toLowerCase()
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: service.copyToClipboard(detail.value)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.tooltip
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: service.connected ? "󰌾" : "󰌿"
          color: root.barIconColor
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) service.toggleVpn()
      else if (buttonCode === Qt.MiddleButton) service.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(480))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: false
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          id: hero
          width: parent.width
          title: "FortiClient VPN"
          meta: root.statusText
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: service.connected ? 1.0 : 0.6
          iconComponent: Component {
            Text {
              text: service.connected ? "󰌾" : "󰌿"
              color: service.vpnState === "failed" ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              visible: service.installed && service.profile !== ""
              checked: service.connected || service.vpnState === "connecting"
              busy: service.busy
              foreground: hero.foreground
              onToggled: service.toggleVpn()

              PanelToolTip {
                text: service.connected ? "Disconnect" : "Connect"
                fontFamily: hero.fontFamily
              }
            }
          }
        }

        Text {
          visible: service.lastError !== ""
          width: parent.width
          text: service.lastError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Column {
          visible: service.hint !== ""
          width: parent.width
          spacing: Style.space(6)

          Text {
            width: parent.width
            text: service.hint === "needsPassword"
              ? "FortiClient has no saved password for this profile. Run this once in a terminal to save it, then connect from here:"
              : "The gateway certificate needs confirming. Run this once in a terminal and accept the certificate:"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            PanelActionButton {
              iconText: "󰆏"
              tooltipText: "Copy command"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: service.copyToClipboard(root.hintCommand)
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(40)
              textFormat: Text.PlainText
              text: root.hintCommand
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }
        }

        Text {
          visible: service.checkedInstalled && !service.installed
          width: parent.width
          text: "The fortivpn command was not found. Install the forticlient-vpn package first."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        PanelSeparator {
          foreground: root.foreground
        }

        PanelSectionHeader {
          text: "SESSION"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          DetailRow { label: "Profile"; value: service.profile }
          DetailRow { label: "Username"; value: service.connected ? service.info.username : "" }
          DetailRow { label: "IP address"; value: service.connected ? service.info.ip : ""; copyable: true }
          DetailRow { label: "Duration"; value: service.connected ? service.info.duration : "" }
          DetailRow { label: "Sent"; value: service.connected ? Model.formatBytes(service.info.sent) : "" }
          DetailRow { label: "Received"; value: service.connected ? Model.formatBytes(service.info.received) : "" }
        }
      }
    }
  }
}
