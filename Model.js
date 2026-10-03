.pragma library

function clean(value) {
  return String(value == null ? "" : value).trim()
}

function emptyInfo() {
  return { status: "", profile: "", username: "", ip: "", sent: -1, received: -1, duration: "" }
}

function parseStatus(text) {
  var info = emptyInfo()
  var lines = String(text || "").split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([A-Za-z ]+?)\s*:\s*(.*)$/)
    if (!m) continue
    var key = m[1].toLowerCase()
    var value = clean(m[2])
    if (key === "status") info.status = value
    else if (key === "vpn name") info.profile = value
    else if (key === "username") info.username = value
    else if (key === "ip") info.ip = value
    else if (key === "sent bytes") info.sent = parseInt(value, 10)
    else if (key === "recv bytes") info.received = parseInt(value, 10)
    else if (key === "duration") info.duration = value
  }
  return info
}

function normalizeState(status) {
  var s = clean(status).toLowerCase()
  if (s === "connected") return "connected"
  if (s.indexOf("disconnecting") !== -1) return "disconnecting"
  if (s.indexOf("connecting") !== -1) return "connecting"
  return "disconnected"
}

// `fortivpn list` prints section headers ending in ":" and indents profile names by four spaces.
function parseProfiles(text) {
  var out = []
  String(text || "").split(/\r?\n/).forEach(function(line) {
    if (!/^\s{4,}\S/.test(line)) return
    var name = clean(line)
    if (name !== "" && !/:$/.test(name)) out.push(name)
  })
  return out
}

function formatBytes(value) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return "—"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024
    i++
  }
  return (i === 0 ? String(n) : n.toFixed(n < 10 ? 2 : 1)) + " " + units[i]
}

function parseConnectLog(text) {
  var body = String(text || "")
  var message = ""
  var notices = body.match(/Notification:\s*(.+)/g)
  if (notices && notices.length > 0) message = clean(notices[notices.length - 1].replace(/^Notification:\s*/, ""))
  return {
    succeeded: /Status:\s*Connected/i.test(body),
    finished: /DONE\./.test(body),
    message: message
  }
}

function failureHint(text) {
  var body = String(text || "")
  if (/Confirmation Required|untrusted server|Login canceled/i.test(body)) return "needsTrust"
  if (/credential|password/i.test(body)) return "needsPassword"
  return ""
}

// fortivpn refuses to run while another fortivpn call is in progress.
function isLockBusy(text) {
  return /Another instance of this program is running/i.test(String(text || ""))
}

// stdin is /dev/null so an unexpected prompt (password, certificate) fails fast instead of hanging.
function connectCommand(profile, logPath) {
  return ["bash", "-c", 'exec fortivpn connect "$1" </dev/null >"$2" 2>&1', "bash", profile, logPath]
}

function terminalConnectCommand(profile, savePassword) {
  return 'fortivpn connect "' + clean(profile).replace(/"/g, '\\"') + '"' + (savePassword ? " -p -s" : "")
}
