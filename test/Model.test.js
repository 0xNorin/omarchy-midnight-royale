// Deterministic unit tests for Model.js (pure, Qt-free logic).
// Runs under plain node: `node test/Model.test.js`. No shell, no network, and
// no downloaded content is executed — every fixture is a local string.
"use strict";

const assert = require("assert");
const M = require("../Model.js");

// ---- Fixtures: `tar -tvf` listings (matching real GNU tar output) ----

// The real pinned 1.0.9 Linux amd64 archive layout.
const TAR_VALID = [
  "-rwxr-xr-x 0/0        28187490 1970-01-01 01:00 midnight-royale",
  "-rwxr-xr-x 0/0             681 1970-01-01 01:00 README.md",
  "-rw-r--r-- 0/0           92328 1970-01-01 01:00 THIRD-PARTY-NOTICES.txt",
].join("\n");

// A regular-file entry whose path traverses upward.
const TAR_TRAVERSAL =
  "-rw-r--r-- 0/0               0 1970-01-01 01:00 ../../etc/passwd\n";

// A regular-file entry with an absolute path.
const TAR_ABSOLUTE =
  "-rw-r--r-- 0/0               0 1970-01-01 01:00 /tmp/evil\n";

// A symbolic-link entry (type 'l').
const TAR_SYMLINK =
  "-rwxr-xr-x 0/0        28187490 1970-01-01 01:00 midnight-royale\n" +
  "lrwxrwxrwx 0/0               0 1970-01-01 01:00 midnight-royale -> /etc/passwd\n";

// A hard-link entry (type 'h').
const TAR_HARDLINK =
  "-rwxr-xr-x 0/0        28187490 1970-01-01 01:00 midnight-royale\n" +
  "hrw-r--r-- 0/0               0 1970-01-01 01:00 other link to midnight-royale\n";

// A device (FIFO) entry — must be rejected as a special type.
const TAR_FIFO =
  "-rwxr-xr-x 0/0        28187490 1970-01-01 01:00 midnight-royale\n" +
  "prw-r--r-- 0/0               0 1970-01-01 01:00 fifo\n";

// A regular-file entry outside the allowed release layout.
const TAR_UNEXPECTED =
  "-rwxr-xr-x 0/0        28187490 1970-01-01 01:00 midnight-royale\n" +
  "-rwxr-xr-x 0/0            1000 1970-01-01 01:00 evil.sh\n";

// ---- Fixtures: stable.json payloads ----

const STABLE_VALID = JSON.stringify({
  app_id: "midnight-royale",
  channel: "stable",
  status: "published",
  version: "1.0.9",
  artifacts: [
    {
      platform: "linux",
      architecture: "amd64",
      download_url: "https://evil.example.com/pwn.tar.gz",
      sha256: "f".repeat(64),
    },
  ],
});

// ---- Helpers ----

let passed = 0;
function test(name, fn) {
  fn();
  passed += 1;
  process.stdout.write("ok - " + name + "\n");
}

// ---- Tests ----

test("parseVersion", () => {
  assert.strictEqual(M.parseVersion("Midnight Royale 1.0.3"), "1.0.3");
  assert.strictEqual(M.parseVersion("Midnight Royale 1.0.3\n"), "1.0.3");
  assert.strictEqual(M.parseVersion("nonsense"), null);
});

test("compareVersions", () => {
  assert.strictEqual(M.compareVersions("1.0.3", "1.0.4"), -1);
  assert.strictEqual(M.compareVersions("1.0.4", "1.0.3"), 1);
  assert.strictEqual(M.compareVersions("1.0.3", "1.0.3"), 0);
  assert.strictEqual(M.compareVersions("1.0.4-rc.1", "1.0.4"), -1);
});

test("parseSha256Sum", () => {
  assert.strictEqual(M.parseSha256Sum("a".repeat(64) + "  /tmp/x.tar.gz"), "a".repeat(64));
  assert.strictEqual(M.parseSha256Sum("A".repeat(64) + "  x"), "a".repeat(64));
  assert.strictEqual(M.parseSha256Sum("nonsense"), null);
});

// Finding 1: pinned bootstrap URL / SHA-256 cannot be replaced by stable.json.
test("pinned bootstrap URL cannot be replaced by stable.json", () => {
  assert.strictEqual(
    M.BOOTSTRAP_URL,
    "https://commerce.0xnorin.app/releases/1.0.9/MidnightRoyale-0xNorin-1.0.9-linux-amd64.tar.gz"
  );
  // parseStableJson must surface a version only — no url/sha keys at all.
  const meta = M.parseStableJson(STABLE_VALID);
  assert.ok(meta !== null);
  assert.strictEqual(meta.version, "1.0.9");
  assert.ok(!("linuxAmd64" in meta));
  assert.ok(!("download_url" in meta));
  assert.ok(!("sha256" in meta));
});

test("pinned SHA-256 cannot be replaced by stable.json", () => {
  assert.strictEqual(
    M.BOOTSTRAP_SHA256,
    "f4caba3728dea40d24f6776d22e002a10d35016014c72c079dd0a715aa2f6f74"
  );
  assert.strictEqual(M.BOOTSTRAP_VERSION, "1.0.9");
  assert.strictEqual(M.BOOTSTRAP_EXECUTABLE, "midnight-royale");
});

// Finding 1: non-approved download hosts are rejected.
test("non-approved download hosts are rejected", () => {
  assert.strictEqual(M.isAllowedHost(M.BOOTSTRAP_URL), true);
  assert.strictEqual(M.isAllowedHost("https://commerce.0xnorin.app/other"), true);
  assert.strictEqual(M.isAllowedHost("https://evil.example.com/pwn.tar.gz"), false);
  assert.strictEqual(M.isAllowedHost("http://commerce.0xnorin.app/x"), false);
  assert.strictEqual(M.isAllowedHost("https://commerce.0xnorin.app.evil.com/x"), false);
  assert.strictEqual(M.isAllowedHost("https://user@commerce.0xnorin.app/x"), false);
  assert.strictEqual(M.isAllowedHost("ftp://commerce.0xnorin.app/x"), false);
  assert.strictEqual(M.isAllowedHost("not a url"), false);
});

// Finding 3: malformed stable.json fails closed.
test("malformed stable.json", () => {
  assert.strictEqual(M.parseStableJson("not json"), null);
  assert.strictEqual(M.parseStableJson("{}"), null);
  assert.strictEqual(M.parseStableJson("null"), null);
  assert.strictEqual(
    M.parseStableJson(JSON.stringify({ app_id: "midnight-royale", channel: "stable", status: "published" })),
    null
  );
  assert.strictEqual(
    M.parseStableJson(JSON.stringify({ app_id: "midnight-royale", channel: "stable", status: "published", version: "banana" })),
    null
  );
  assert.strictEqual(
    M.parseStableJson(JSON.stringify({ app_id: "other-app", channel: "stable", status: "published", version: "1.0.9" })),
    null
  );
});

// Finding 3: oversized metadata fails closed (64 KiB cap).
test("oversized metadata is rejected", () => {
  assert.strictEqual(M.METADATA_MAX_BYTES, 65536);
  // Just under the cap: accepted. Over the cap: rejected.
  const small = JSON.stringify({ app_id: "midnight-royale", channel: "stable", status: "published", version: "1.0.9", pad: "" });
  assert.ok(M.parseStableJson(small) !== null);
  const over = "x".repeat(M.METADATA_MAX_BYTES + 1);
  assert.strictEqual(M.parseStableJson(over), null);
  const bigValid = JSON.stringify({ app_id: "midnight-royale", channel: "stable", status: "published", version: "1.0.9", pad: "x".repeat(M.METADATA_MAX_BYTES) });
  assert.strictEqual(M.parseStableJson(bigValid), null);
});

// Finding 2: archive entry validation.
test("archive path traversal rejection", () => {
  assert.strictEqual(M.validateTarList(TAR_TRAVERSAL).ok, false);
});

test("absolute archive path rejection", () => {
  assert.strictEqual(M.validateTarList(TAR_ABSOLUTE).ok, false);
});

test("symlink rejection", () => {
  assert.strictEqual(M.validateTarList(TAR_SYMLINK).ok, false);
});

test("hardlink rejection", () => {
  assert.strictEqual(M.validateTarList(TAR_HARDLINK).ok, false);
});

test("unexpected (special) archive member rejection", () => {
  assert.strictEqual(M.validateTarList(TAR_FIFO).ok, false);
});

test("unexpected (out-of-layout) archive member rejection", () => {
  assert.strictEqual(M.validateTarList(TAR_UNEXPECTED).ok, false);
});

test("valid expected archive acceptance", () => {
  const v = M.validateTarList(TAR_VALID);
  assert.strictEqual(v.ok, true, v.reason);
});

test("missing executable rejection", () => {
  const noExe = "-rwxr-xr-x 0/0 681 1970-01-01 01:00 README.md\n";
  assert.strictEqual(M.validateTarList(noExe).ok, false);
});

// Finding 4: checksum mismatch aborts.
test("checksum mismatch abort", () => {
  assert.strictEqual(M.verifyChecksum(M.BOOTSTRAP_SHA256 + "  archive", M.BOOTSTRAP_SHA256), true);
  assert.strictEqual(M.verifyChecksum("b".repeat(64) + "  archive", M.BOOTSTRAP_SHA256), false);
  assert.strictEqual(M.verifyChecksum("nonsense", M.BOOTSTRAP_SHA256), false);
  assert.strictEqual(M.verifyChecksum(M.BOOTSTRAP_SHA256 + "  archive", "not-a-digest"), false);
});

// Finding 5: update-check six-hour throttle.
test("update-check six-hour throttle", () => {
  const WINDOW = 6 * 60 * 60 * 1000;
  const now = 1_800_000_000_000; // arbitrary fixed epoch
  assert.strictEqual(M.isUpdateCheckDue(false, now - WINDOW / 2, now), false); // fresh
  assert.strictEqual(M.isUpdateCheckDue(false, now - WINDOW, now), true); // exactly stale
  assert.strictEqual(M.isUpdateCheckDue(false, now - WINDOW - 1, now), true); // stale
  assert.strictEqual(M.isUpdateCheckDue(false, 0, now), true); // never checked
});

test("explicit manual refresh bypasses throttle", () => {
  const now = 1_800_000_000_000;
  assert.strictEqual(M.isUpdateCheckDue(true, now - 1000, now), true); // forced + fresh
  assert.strictEqual(M.isUpdateCheckDue(true, 0, now), true);
});

console.log("\nAll " + passed + " Model.js tests passed.");
