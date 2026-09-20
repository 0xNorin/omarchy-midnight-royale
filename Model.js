// Pure, Qt-free state and parsing logic for the Midnight Royale bar widget.
// Kept out of the QML so it can be unit-tested under node (see
// .github/workflows/validate.yml) without a shell. The QML owns process
// spawning, network I/O and rendering; everything here is a pure function of
// its arguments.

var APP_ID = "app.0xnorin.midnight-royale"

// Official URLs. The plugin opens these in a browser; it never runs an
// installer script from them.
var WEBSITE_URL = "https://0xnorin.app/midnight-royale/"

// The public, unsigned release record the website consumes. The install and
// update checks read this for the current version, the Linux artifact URL and
// its SHA-256. It is a convenience hint, not a cryptographic trust boundary:
// downloads are verified against this checksum for integrity, while the
// game's own signed updater remains the signature-verifying trust path.
var UPDATE_METADATA_URL = "https://commerce.0xnorin.app/releases/stable.json"

// ---- Status keys ----
var STATUS_CHECKING = "checking"
var STATUS_NOT_INSTALLED = "not-installed"
var STATUS_INSTALLING = "installing"
var STATUS_INSTALLED = "installed"
var STATUS_INSTALLED_UNPARSED = "installed-unparsed"

// ---- Update states (only meaningful once STATUS_INSTALLED) ----
var UPDATE_CURRENT = "current"
var UPDATE_AVAILABLE = "update"
var UPDATE_UNAVAILABLE = "unavailable"

// "Midnight Royale 1.0.3" -> "1.0.3"; null when the shape doesn't match.
// Parses defensively: a malformed or unexpected output is "not parsed",
// never a crash and never a false version.
function parseVersion(output) {
  var text = String(output === undefined || output === null ? "" : output)
  var match = /^\s*Midnight Royale\s+([^\s]+)\s*$/.exec(text)
  if (!match) return null
  var candidate = match[1]
  return validSemver(candidate) ? candidate : null
}

function validSemver(raw) {
  var s = String(raw === undefined || raw === null ? "" : raw)
  var core = s.split("+")[0]
  var corePre = core.split("-")[0]
  var parts = corePre.split(".")
  if (parts.length !== 3) return false
  for (var i = 0; i < 3; i++) {
    if (!/^\d+$/.test(parts[i])) return false
    if (parts[i].length > 1 && parts[i][0] === "0") return false
  }
  return true
}

// -1 if a < b, 0 if equal, 1 if a > b. A pre-release sorts before its release.
function compareVersions(a, b) {
  var av = parseSemver(a)
  var bv = parseSemver(b)
  for (var i = 0; i < 3; i++) {
    if (av.nums[i] !== bv.nums[i]) return av.nums[i] < bv.nums[i] ? -1 : 1
  }
  if (av.pre.length === 0 && bv.pre.length === 0) return 0
  if (av.pre.length === 0) return 1
  if (bv.pre.length === 0) return -1
  var n = Math.min(av.pre.length, bv.pre.length)
  for (var j = 0; j < n; j++) {
    if (av.pre[j] === bv.pre[j]) continue
    var an = /^\d+$/.test(av.pre[j])
    var bn = /^\d+$/.test(bv.pre[j])
    if (an && bn) return parseInt(av.pre[j], 10) < parseInt(bv.pre[j], 10) ? -1 : 1
    if (an) return -1
    if (bn) return 1
    return av.pre[j] < bv.pre[j] ? -1 : 1
  }
  return av.pre.length === bv.pre.length ? 0 : (av.pre.length < bv.pre.length ? -1 : 1)
}

function parseSemver(raw) {
  var s = String(raw === undefined || raw === null ? "" : raw)
  var core = s.split("+")[0]
  var corePre = core.split("-")
  var nums = corePre[0].split(".").map(function (p) { return parseInt(p, 10) })
  var pre = corePre.length > 1 ? corePre.slice(1).join("-").split(".") : []
  if (pre.length === 1 && pre[0] === "") pre = []
  return { nums: nums, pre: pre }
}

// Parse the public stable release record defensively. Returns
// { version, linuxAmd64 } where linuxAmd64 is { url, sha256 } for the Linux
// x86_64 artifact, or null for anything malformed, withdrawn, wrong-app or
// wrong-channel. linuxAmd64 is null when no valid Linux artifact is present.
function parseStableJson(text) {
  var s = String(text === undefined || text === null ? "" : text)
  if (!s) return null
  var data = null
  try { data = JSON.parse(s) } catch (e) { return null }
  if (!data || typeof data !== "object") return null
  if (data.app_id !== "midnight-royale") return null
  if (data.channel !== "stable") return null
  if (data.status !== "published") return null
  if (typeof data.version !== "string" || !validSemver(data.version)) return null

  var linuxAmd64 = null
  if (Array.isArray(data.artifacts)) {
    for (var i = 0; i < data.artifacts.length; i++) {
      var a = data.artifacts[i]
      if (!a || typeof a !== "object") continue
      if (a.platform !== "linux" || a.architecture !== "amd64") continue
      if (typeof a.download_url !== "string" || a.download_url.indexOf("https://") !== 0) continue
      if (typeof a.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(a.sha256)) continue
      linuxAmd64 = { url: a.download_url, sha256: a.sha256 }
      break
    }
  }
  return { version: data.version, linuxAmd64: linuxAmd64 }
}

// First 64-hex digest out of a `sha256sum` line ("<hash>  <file>"), or null.
function parseSha256Sum(output) {
  var s = String(output === undefined || output === null ? "" : output).trim()
  var match = /^([0-9a-fA-F]{64})\b/.exec(s)
  return match ? match[1].toLowerCase() : null
}

// ---- Display strings (pure; QML binds these) ----

function statusTitle(statusKey, installedVersion) {
  switch (statusKey) {
    case STATUS_NOT_INSTALLED: return "Midnight Royale is not installed"
    case STATUS_INSTALLING: return "Installing Midnight Royale\u2026"
    case STATUS_INSTALLED_UNPARSED: return "Midnight Royale is installed"
    case STATUS_CHECKING: return "Checking Midnight Royale\u2026"
    default: return "Installed \u00b7 v" + installedVersion
  }
}

function statusSubtitle(statusKey, updateState, latestVersion) {
  if (statusKey === STATUS_CHECKING || statusKey === STATUS_INSTALLING) return ""
  if (statusKey === STATUS_NOT_INSTALLED) return ""
  if (statusKey === STATUS_INSTALLED_UNPARSED) return "Version unavailable"
  if (updateState === UPDATE_AVAILABLE) return "Update available \u00b7 v" + latestVersion
  if (updateState === UPDATE_UNAVAILABLE) return "Unable to check for updates"
  return "Up to date"
}

if (typeof module !== "undefined") {
  module.exports = {
    APP_ID: APP_ID,
    WEBSITE_URL: WEBSITE_URL,
    UPDATE_METADATA_URL: UPDATE_METADATA_URL,
    STATUS_CHECKING: STATUS_CHECKING,
    STATUS_NOT_INSTALLED: STATUS_NOT_INSTALLED,
    STATUS_INSTALLING: STATUS_INSTALLING,
    STATUS_INSTALLED: STATUS_INSTALLED,
    STATUS_INSTALLED_UNPARSED: STATUS_INSTALLED_UNPARSED,
    UPDATE_CURRENT: UPDATE_CURRENT,
    UPDATE_AVAILABLE: UPDATE_AVAILABLE,
    UPDATE_UNAVAILABLE: UPDATE_UNAVAILABLE,
    parseVersion: parseVersion,
    validSemver: validSemver,
    compareVersions: compareVersions,
    parseStableJson: parseStableJson,
    parseSha256Sum: parseSha256Sum,
    statusTitle: statusTitle,
    statusSubtitle: statusSubtitle
  }
}
