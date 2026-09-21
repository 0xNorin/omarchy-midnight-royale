// Pure, Qt-free state and parsing logic for the Midnight Royale bar widget.
// Kept out of the QML so it can be unit-tested under node (see
// .github/workflows/validate.yml and test/Model.test.js) without a shell. The
// QML owns process spawning, network I/O and rendering; everything here is a
// pure function of its arguments.

var APP_ID = "app.0xnorin.midnight-royale"

// Official URL. The plugin opens this in a browser; it never runs an
// installer script from it.
var WEBSITE_URL = "https://0xnorin.app/midnight-royale/"

// ---- Bootstrap install trust boundary (PINNED, reviewed in source) ----
//
// The FIRST installation does not trust any remote, unsigned metadata. The
// artifact URL, version and SHA-256 below are pinned in this reviewed source
// and were independently confirmed against the production release material
// (the release's own SHA256SUMS.txt) when this patch was prepared. A bootstrap
// install downloads exactly this artifact from exactly this host and verifies
// exactly this digest. Nothing fetched from the network can change these
// values.
//
// Future application updates are delegated to Midnight Royale's own signed
// updater; this plugin never re-implements it.
var BOOTSTRAP_VERSION = "1.0.9"
var BOOTSTRAP_URL = "https://commerce.0xnorin.app/releases/1.0.9/MidnightRoyale-0xNorin-1.0.9-linux-amd64.tar.gz"
var BOOTSTRAP_SHA256 = "f4caba3728dea40d24f6776d22e002a10d35016014c72c079dd0a715aa2f6f74"

// The only host a bootstrap download may target. The pinned URL above is
// already on this host; this allowlist is an independent, defense-in-depth
// check applied before any download.
var ALLOWED_DOWNLOAD_HOST = "commerce.0xnorin.app"

// The exact, flat release layout of the pinned bootstrap archive. Every
// archive member must be one of these regular files; the executable that gets
// installed is BOOTSTRAP_EXECUTABLE. Anything else (directories, symlinks,
// hardlinks, devices, FIFOs, extra files, nested paths) is rejected.
var BOOTSTRAP_ALLOWED_MEMBERS = ["midnight-royale", "README.md", "THIRD-PARTY-NOTICES.txt"]
var BOOTSTRAP_EXECUTABLE = "midnight-royale"

// The public, unsigned release record the website consumes. This is
// DISPLAY-ONLY update metadata: it is read to show whether a newer version
// exists. It never supplies an artifact URL or a checksum, and it never
// decides what gets installed or trusted.
var UPDATE_METADATA_URL = "https://commerce.0xnorin.app/releases/stable.json"

// Strict size cap for the release metadata response (64 KiB), in addition to
// the timeout. Oversized responses fail closed into "update unavailable".
var METADATA_MAX_BYTES = 65536

// Six-hour freshness window for the display-only update check. Local
// installation/version detection still runs every time the panel opens; the
// network metadata fetch runs at most once per window. A deliberate Retry
// bypasses the window.
var UPDATE_CHECK_WINDOW_MS = 6 * 60 * 60 * 1000

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

// Parse the public stable release record defensively, DISPLAY-ONLY. Returns
// { version } for a valid, published, stable record, or null for anything
// malformed, withdrawn, wrong-app or wrong-channel. An oversized response
// (beyond METADATA_MAX_BYTES) is rejected before parsing. Artifact URLs and
// checksums are deliberately NOT read from this unsigned record.
function parseStableJson(text) {
  var s = String(text === undefined || text === null ? "" : text)
  if (!s) return null
  if (s.length > METADATA_MAX_BYTES) return null
  var data = null
  try { data = JSON.parse(s) } catch (e) { return null }
  if (!data || typeof data !== "object") return null
  if (data.app_id !== "midnight-royale") return null
  if (data.channel !== "stable") return null
  if (data.status !== "published") return null
  if (typeof data.version !== "string" || !validSemver(data.version)) return null
  return { version: data.version }
}

// First 64-hex digest out of a `sha256sum` line ("<hash>  <file>"), or null.
function parseSha256Sum(output) {
  var s = String(output === undefined || output === null ? "" : output).trim()
  var match = /^([0-9a-fA-F]{64})\b/.exec(s)
  return match ? match[1].toLowerCase() : null
}

// True only when the `sha256sum` output matches the expected 64-hex digest.
// The digest is compared exactly; a mismatch must abort the install.
function verifyChecksum(sumOutput, expectedSha256) {
  var actual = parseSha256Sum(sumOutput)
  if (actual === null) return false
  var expected = String(expectedSha256 === undefined || expectedSha256 === null ? "" : expectedSha256).toLowerCase()
  if (!/^[0-9a-f]{64}$/.test(expected)) return false
  return actual === expected
}

// True only for an HTTPS URL whose host (ignoring an optional port) is exactly
// the allowlisted download host. Rejects http://, userinfo, ports on other
// hosts, and anything not matching the expected shape.
function isAllowedHost(url) {
  var s = String(url === undefined || url === null ? "" : url)
  var m = /^https:\/\/([A-Za-z0-9.-]+)(?::\d+)?(?:\/|$)/.exec(s)
  if (!m) return false
  return m[1] === ALLOWED_DOWNLOAD_HOST
}

// Validate the verbose listing (`tar -tvf`) of the bootstrap archive BEFORE
// extraction. Returns { ok, reason }. Rejects any entry that is not a regular
// file, that has an unsafe or unexpected path, or that is outside the pinned
// allowed release layout; requires the expected executable to be present
// exactly once.
function validateTarList(listing) {
  var text = String(listing === undefined || listing === null ? "" : listing)
  var lines = text.split("\n")
  var seen = {}
  var foundExecutable = false
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/\s+$/, "")
    if (line === "") continue
    // The first character of a `tar -tvf` line is the entry type: '-' regular,
    // 'd' directory, 'l' symlink, 'h' hardlink, 'b'/'c' device, 'p' FIFO, ...
    var type = line[0]
    if (type !== "-") {
      return { ok: false, reason: "non-regular archive entry (type '" + type + "')" }
    }
    var m = /^\S+\s+\S+\s+\d+\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(?::\d{2})?\s+(.+)$/.exec(line)
    if (!m) {
      return { ok: false, reason: "unparseable archive entry" }
    }
    var name = m[1]
    if (isUnsafeArchivePath(name)) {
      return { ok: false, reason: "unsafe archive entry path: " + name }
    }
    if (BOOTSTRAP_ALLOWED_MEMBERS.indexOf(name) === -1) {
      return { ok: false, reason: "archive entry outside allowed release layout: " + name }
    }
    if (seen[name]) {
      return { ok: false, reason: "duplicate archive entry: " + name }
    }
    seen[name] = true
    if (name === BOOTSTRAP_EXECUTABLE) foundExecutable = true
  }
  if (!foundExecutable) {
    return { ok: false, reason: "expected executable '" + BOOTSTRAP_EXECUTABLE + "' missing from archive" }
  }
  return { ok: true, reason: "" }
}

// A single archive member name is unsafe if it is empty, absolute, a Windows
// drive path, contains a ".." segment or a backslash, or contains a NUL byte.
function isUnsafeArchivePath(name) {
  var s = String(name === undefined || name === null ? "" : name)
  if (s === "") return true
  if (s[0] === "/") return true
  if (/^[A-Za-z]:/.test(s)) return true
  if (s.indexOf("\\") !== -1) return true
  if (s.indexOf("\u0000") !== -1) return true
  var parts = s.split("/")
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] === "..") return true
  }
  return false
}

// True when a display-only update check should run now: always when forced
// (manual Retry), and otherwise only when the previous check is at least
// UPDATE_CHECK_WINDOW_MS old (or never happened).
function isUpdateCheckDue(forced, lastCheckEpochMs, nowEpochMs) {
  if (forced) return true
  var last = Number(lastCheckEpochMs)
  var now = Number(nowEpochMs)
  if (!isFinite(last) || !isFinite(now) || last <= 0) return true
  return (now - last) >= UPDATE_CHECK_WINDOW_MS
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
    BOOTSTRAP_VERSION: BOOTSTRAP_VERSION,
    BOOTSTRAP_URL: BOOTSTRAP_URL,
    BOOTSTRAP_SHA256: BOOTSTRAP_SHA256,
    ALLOWED_DOWNLOAD_HOST: ALLOWED_DOWNLOAD_HOST,
    BOOTSTRAP_ALLOWED_MEMBERS: BOOTSTRAP_ALLOWED_MEMBERS,
    BOOTSTRAP_EXECUTABLE: BOOTSTRAP_EXECUTABLE,
    METADATA_MAX_BYTES: METADATA_MAX_BYTES,
    UPDATE_CHECK_WINDOW_MS: UPDATE_CHECK_WINDOW_MS,
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
    verifyChecksum: verifyChecksum,
    isAllowedHost: isAllowedHost,
    validateTarList: validateTarList,
    isUpdateCheckDue: isUpdateCheckDue,
    statusTitle: statusTitle,
    statusSubtitle: statusSubtitle
  }
}
