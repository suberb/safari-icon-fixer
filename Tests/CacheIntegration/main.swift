import Foundation
import AppKit
import Darwin

// Entirely synthetic Safari directory and support root. Never touches the actual profile.
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("sif-cache-integration-" + UUID().uuidString, isDirectory: true)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
let host = "example.test"
let original = demoArtwork(0)
let edited = demoArtwork(1)
let other = demoArtwork(2)
let originalState: PersonalizationState = {
    var s = PersonalizationState(); s.remember(host: host, png: original, digest: iconDigest(original), display: nil); return s
}()
func check(_ test: @autoclosure () throws -> Bool, file: StaticString = #file, line: UInt = #line) throws { let value = try test(); precondition(value, file: file, line: line) }
func reject(_ work: () throws -> Void) { do { try work(); fatalError("Expected failure") } catch {} }
func make(_ flag: String, _ display: Bool) throws -> Cache {
    let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let c = Cache(safari: dir.appendingPathComponent("Safari", isDirectory: true), supportRoot: dir.appendingPathComponent("Support", isDirectory: true), runningOverride: { false })
    try fm.createDirectory(at: c.images, withIntermediateDirectories: true)
    let plist: [String:Any] = ["Title":"root","Children":[["Title":"BookmarksBar","Children":[["URLString":"https://\(host)/","URIDictionary":["title":"Example"]]]]]]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: c.safari.appendingPathComponent("Bookmarks.plist"))
    _ = try sql(c.db, "CREATE TABLE cache_settings(host TEXT PRIMARY KEY, \(flag) INT, download_status_flags INT, extra TEXT\(display ? ", transparency_analysis_result INT" : "")); INSERT INTO cache_settings VALUES ('\(host)',1,1,'keep'\(display ? ",0" : "")); INSERT INTO cache_settings VALUES ('other.test',1,1,'other'\(display ? ",0" : ""));", write: true)
    try original.write(to: c.icon(host)); try other.write(to: c.icon("other.test")); try c.savePersonalization(originalState)
    return c
}
func clone(_ c: Cache, fault: ((String) throws -> Void)? = nil, open: Bool = false) -> Cache {
    Cache(safari: c.safari, supportRoot: c.journal.root, runningOverride: { open }, fault: fault)
}
func intact(_ c: Cache, _ flag: String) throws {
    try check(try Data(contentsOf: c.icon(host)) == original)
    try check(try Data(contentsOf: c.icon("other.test")) == other)
    try check(try c.personalization() == originalState)
    let r = try rows(c.db, "SELECT \(flag) AS active, download_status_flags AS download, extra FROM cache_settings WHERE host='\(host)';")
    precondition(r[0]["active"] as? Int == 1 && r[0]["download"] as? Int == 1 && r[0]["extra"] as? String == "keep")
    try check(try c.journal.read() == nil)
}
struct Interrupted: Error {}
// Child exits without Swift unwinding, then the parent explicitly recovers the journal.
if CommandLine.arguments.count == 5 && CommandLine.arguments[1] == "--interrupt" {
    let c = Cache(safari: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true), supportRoot: URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true), runningOverride: { false }, fault: { point in
        if point == CommandLine.arguments[4] { _exit(73) }
    })
    let item = Pending(png: edited, source: "test", custom: true, expectedDigest: iconDigest(try Data(contentsOf: c.icon(host))))
    _ = try c.apply([host:item], allowingReplacement:[host], scope:.all)
    _exit(74)
}

for flag in ["touch_icon_is_in_cache", "icon_is_in_cache"] {
    for display in [false, true] {
        let c = try make(flag, display)
        let bookmark = try Data(contentsOf: c.safari.appendingPathComponent("Bookmarks.plist"))
        try check(try c.schema() == flag && c.hasDisplayColumn() == display)
        let item = Pending(png: edited, source: "test", custom: true, display: display ? .fullTile : nil, expectedDigest: iconDigest(original))
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--interrupt", c.safari.path, c.journal.root.path, "database-committed"]
        try child.run(); child.waitUntilExit()
        precondition(child.terminationReason == .exit && child.terminationStatus == 73)
        try check(try c.journal.read() != nil)
        try clone(c).recoverInterruptedWrite(); try intact(c,flag)
        for point in ["image-written", "personalization-written", "database-committed"] {
            let bad = clone(c, fault: { if $0 == point { throw Interrupted() } })
            reject { _ = try bad.apply([host:item], allowingReplacement:[host], scope:.all) }
            try check(try c.journal.read() != nil)
            reject { try clone(c,open:true).recoverInterruptedWrite() }
            reject { _ = try c.reset([host], scope:.all, trackedOnly:false) }
            try clone(c).recoverInterruptedWrite()
            try intact(c,flag)
        }
        for point in ["image-removed", "personalization-written", "database-committed"] {
            reject { _ = try clone(c,fault:{ if $0 == point { throw Interrupted() } }).reset([host], scope:.all, trackedOnly:false) }
            try check(try c.journal.read() != nil)
            try clone(c).recoverInterruptedWrite(); try intact(c,flag)
        }
        let old = try c.apply([host:item], allowingReplacement:[host], scope:.all).0
        try check(try Data(contentsOf: c.icon(host)) == edited && c.journal.read() == nil)
        // Legacy copies lack metadata; restore their cache, keep the protected collection.
        let legacy = c.backups.appendingPathComponent(UUID().uuidString)
        try fm.copyItem(at: old,to:legacy); try fm.removeItem(at: legacy.appendingPathComponent("SIF-Personalization.json"))
        let currentState = try c.personalization()
        _ = try c.restore(legacy)
        try check(try Data(contentsOf: c.icon(host)) == original && c.personalization() == currentState)
        // Modern snapshots restore matching registry and image data.
        _ = try c.restore(old); try intact(c,flag)
        for point in ["cache-displaced", "cache-installed", "personalization-written"] {
            reject { _ = try clone(c,fault:{ if $0 == point { throw Interrupted() } }).restore(old) }
            reject { try clone(c,fault:{ if $0 == "cache-installed" { throw Interrupted() } }).recoverInterruptedWrite() }
            try clone(c).recoverInterruptedWrite(); try intact(c,flag)
        }
        // Reject changed schema before backing up or replacing live cache.
        let incompatible = c.backups.appendingPathComponent(UUID().uuidString)
        try fm.copyItem(at: old,to:incompatible)
        _ = try sql(incompatible.appendingPathComponent("TouchIconCacheSettings.db"),"ALTER TABLE cache_settings ADD COLUMN future INT;",write:true)
        reject { _ = try c.restore(incompatible) }; try intact(c,flag)
        let damaged = c.backups.appendingPathComponent(UUID().uuidString)
        try fm.copyItem(at: old,to:damaged)
        try Data("invalid database".utf8).write(to:damaged.appendingPathComponent("TouchIconCacheSettings.db"))
        reject { _ = try c.restore(damaged) }; try intact(c,flag)
        try check(try Data(contentsOf: c.safari.appendingPathComponent("Bookmarks.plist")) == bookmark)
    }
}
print("OK: synthetic real Cache apply/reset/restore, fault injection, repeated recovery, four layouts, legacy/current copies, corrupt/incompatible copies, Safari running guard, unrelated icons and bookmarks")
