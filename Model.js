// Pure, Qt-free state and parsing logic for the Midnight Royale bar widget.
// Kept out of the QML so it can be unit-tested under node (see
// .github/workflows/validate.yml) without a shell. The QML owns process
// spawning, network I/O and rendering; everything here is a pure function of
// its arguments.

var APP_ID = "app.0xnorin.midnight-royale"

// Official URLs. The plugin only ever opens these; it never runs an
// installer, requests sudo, or downloads anything itself.
var WEBSITE_URL = "https://0xnorin.app/midnight-royale/"
var INSTALL_URL = "https://0xnorin.app/midnight-royale/install/"
var INSTALL_UPDATES_URL = "https://0xnorin.app/midnight-royale/install/"

// The public, unsigned release record the website consumes. It is read ONLY
// as a display hint for "a newer version exists". It is not a trust boundary:
// any real update is delegated to the game's signed updater and is never
// reimplemented in this plugin.
var UPDATE_METADATA_URL = "https://commerce.0xnorin.app/releases/stable.json"

// ---- Status keys ----
var STATUS_CHECKING = "checking"
var STATUS_NOT_INSTALLED = "not-installed"
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
// { version: "1.0.3" } for a well-formed published stable record, or null for
// anything malformed, withdrawn, wrong-app or wrong-channel.
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
  return { version: data.version }
}

// ---- Display strings (pure; QML binds these) ----

function statusTitle(statusKey, installedVersion) {
  switch (statusKey) {
    case STATUS_NOT_INSTALLED: return "Midnight Royale is not installed"
    case STATUS_INSTALLED_UNPARSED: return "Midnight Royale is installed"
    case STATUS_CHECKING: return "Checking Midnight Royale\u2026"
    default: return "Installed \u00b7 v" + installedVersion
  }
}

function statusSubtitle(statusKey, updateState, latestVersion) {
  if (statusKey === STATUS_CHECKING) return ""
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
    INSTALL_URL: INSTALL_URL,
    INSTALL_UPDATES_URL: INSTALL_UPDATES_URL,
    UPDATE_METADATA_URL: UPDATE_METADATA_URL,
    STATUS_CHECKING: STATUS_CHECKING,
    STATUS_NOT_INSTALLED: STATUS_NOT_INSTALLED,
    STATUS_INSTALLED: STATUS_INSTALLED,
    STATUS_INSTALLED_UNPARSED: STATUS_INSTALLED_UNPARSED,
    UPDATE_CURRENT: UPDATE_CURRENT,
    UPDATE_AVAILABLE: UPDATE_AVAILABLE,
    UPDATE_UNAVAILABLE: UPDATE_UNAVAILABLE,
    parseVersion: parseVersion,
    validSemver: validSemver,
    compareVersions: compareVersions,
    parseStableJson: parseStableJson,
    statusTitle: statusTitle,
    statusSubtitle: statusSubtitle
  }
}
