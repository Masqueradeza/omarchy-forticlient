import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool checkedInstalled: false
  // disconnected | connecting | connected | disconnecting | failed
  property string vpnState: "disconnected"
  property var profiles: []
  property var info: Model.emptyInfo()
  property string lastError: ""
  property string hint: ""

  // fortivpn runs one instance at a time, and each bar (one per monitor) runs its own copy of this service.
  readonly property int maxLockRetries: 10
  property int _connectAttempts: 0
  property int _disconnectAttempts: 0

  readonly property string configuredProfile: Model.clean(settings ? settings.profile : "")
  readonly property string profile: configuredProfile !== "" ? configuredProfile
    : (info.profile !== "" ? info.profile : (profiles.length > 0 ? profiles[0] : ""))
  readonly property int refreshIntervalSec: {
    var n = parseInt(String(settings && settings.refreshIntervalSec !== undefined ? settings.refreshIntervalSec : 3), 10)
    return isFinite(n) ? Math.max(1, Math.min(60, n)) : 3
  }
  readonly property string logPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/marcd-forticlient-connect.log"
  readonly property bool connected: vpnState === "connected"
  readonly property bool busy: vpnState === "connecting" || vpnState === "disconnecting"
  readonly property bool canConnect: installed && profile !== "" && !busy && !connected
  readonly property bool canDisconnect: installed && (connected || vpnState === "connecting")

  function refresh() {
    if (!whichProcess.running) whichProcess.running = true
  }

  function refreshStatus() {
    if (installed && vpnState !== "disconnecting" && !statusProcess.running) statusProcess.running = true
  }

  function connectVpn() {
    if (!canConnect) return
    lastError = ""
    hint = ""
    vpnState = "connecting"
    _connectAttempts = 0
    _launchConnect()
  }

  function _launchConnect() {
    _connectAttempts += 1
    Quickshell.execDetached(Model.connectCommand(profile, logPath))
    connectWatch.restart()
  }

  function disconnectVpn() {
    if (!canDisconnect || disconnectProcess.running) return
    connectWatch.stop()
    vpnState = "disconnecting"
    _disconnectAttempts = 0
    _runDisconnect()
  }

  function _runDisconnect() {
    if (disconnectProcess.running) return
    _disconnectAttempts += 1
    disconnectProcess.running = true
  }

  function toggleVpn() {
    if (canDisconnect) disconnectVpn()
    else if (canConnect) connectVpn()
  }

  function copyToClipboard(value) {
    var text = String(value || "")
    if (text !== "") Quickshell.execDetached(["bash", "-c", 'printf %s "$1" | wl-copy', "bash", text])
  }

  function _handleStatus(text) {
    var next = Model.parseStatus(text)
    // No Status line means the call itself failed (usually the single-instance lock), not that the VPN dropped.
    if (next.status === "" || vpnState === "disconnecting") return
    var s = Model.normalizeState(next.status)
    info = next
    if (s === "connected") {
      vpnState = "connected"
      lastError = ""
      hint = ""
      connectWatch.stop()
      return
    }
    if (vpnState === "connecting" || (vpnState === "failed" && s === "disconnected")) return
    vpnState = s
  }

  function _handleLog(text) {
    if (vpnState !== "connecting") return
    var result = Model.parseConnectLog(text)
    var lockBusy = Model.isLockBusy(text)
    if (result.succeeded) {
      connectWatch.stop()
      vpnState = "connected"
      lastError = ""
      hint = ""
      refreshStatus()
      return
    }
    if (lockBusy && _connectAttempts < maxLockRetries) {
      _launchConnect()
      return
    }
    if (!result.finished && !lockBusy) return
    connectWatch.stop()
    vpnState = "failed"
    if (lockBusy) lastError = "FortiClient stayed busy. Try connecting again."
    else lastError = result.message !== "" ? result.message : "FortiClient could not connect."
    hint = Model.failureHint(text)
  }

  function _handleDisconnect(text) {
    var lockBusy = Model.isLockBusy(text)
    if (lockBusy && _disconnectAttempts < maxLockRetries) {
      disconnectRetry.restart()
      return
    }
    if (lockBusy) lastError = "FortiClient stayed busy, so the VPN may still be connected."
    vpnState = "disconnected"
    refreshStatus()
  }

  Timer {
    id: pollTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    onTriggered: root.refreshStatus()
  }

  // Random first poll so the per-monitor copies don't all call fortivpn at the same instant.
  Timer {
    id: pollStagger
    interval: Math.floor(Math.random() * root.refreshIntervalSec * 1000)
    onTriggered: {
      root.refreshStatus()
      pollTimer.start()
    }
  }

  Timer {
    id: disconnectRetry
    interval: 500
    onTriggered: root._runDisconnect()
  }

  Timer {
    id: connectWatch
    property int ticks: 0
    interval: 1000
    repeat: true
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      ticks += 1
      root.refreshStatus()
      if (!logProcess.running) logProcess.running = true
      if (ticks >= 45) {
        running = false
        if (root.vpnState === "connecting") {
          root.vpnState = "failed"
          root.lastError = "Timed out waiting for the VPN to connect."
        }
      }
    }
  }

  Component.onCompleted: refresh()

  Process {
    id: whichProcess
    command: ["bash", "-c", "command -v fortivpn"]
    onExited: function(exitCode) {
      root.checkedInstalled = true
      root.installed = exitCode === 0
      if (!root.installed) return
      if (!pollTimer.running) pollStagger.restart()
      if (!listProcess.running) listProcess.running = true
    }
  }

  Process {
    id: statusProcess
    command: ["fortivpn", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._handleStatus(text) }
  }

  Process {
    id: listProcess
    command: ["fortivpn", "list"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.profiles = Model.parseProfiles(text) }
  }

  Process {
    id: logProcess
    command: ["cat", root.logPath]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._handleLog(text) }
  }

  Process {
    id: disconnectProcess
    command: ["bash", "-c", "fortivpn disconnect 2>&1"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._handleDisconnect(text) }
  }
}
