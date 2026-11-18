import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("sif-recovery-" + UUID().uuidString)
defer { try? fm.removeItem(at: root) }
let backups = root.appendingPathComponent("Backups", isDirectory: true)
let snapshot = backups.appendingPathComponent(UUID().uuidString, isDirectory: true)
try fm.createDirectory(at: snapshot, withIntermediateDirectories: true)
try Data([1,2,3]).write(to: snapshot.appendingPathComponent("fixture"))
let j = RecoveryJournal(root: root)
func rejects(_ body: () throws -> Void) { do { try body(); fatalError("Expected rejection") } catch {} }
precondition(try! j.read() == nil)
try j.withLock { try j.begin(snapshot: snapshot) }
let record = try j.read()!
precondition(record.snapshot.uuidString == snapshot.lastPathComponent)
precondition(j.snapshot(record).standardizedFileURL.path == snapshot.standardizedFileURL.path)
rejects { try j.begin(snapshot: snapshot) }
rejects { try j.withLock { try j.withLock {} } }
// Fresh object simulates a process restart; marker survives until explicit completion.
let restarted = RecoveryJournal(root: root)
precondition(try! restarted.read() == record)
try restarted.withLock { try restarted.finish() }
precondition(try! restarted.read() == nil)
try Data("corrupt".utf8).write(to: j.marker)
rejects { _ = try j.read() }
try fm.removeItem(at: j.marker)
try fm.createSymbolicLink(at: j.marker, withDestinationURL: snapshot.appendingPathComponent("fixture"))
rejects { _ = try j.read() }
try fm.removeItem(at: j.marker)
try fm.createSymbolicLink(at: snapshot.appendingPathComponent("link"), withDestinationURL: root)
rejects { try j.begin(snapshot: snapshot) }
precondition(try! j.read() == nil)
for flag in ["touch_icon_is_in_cache", "icon_is_in_cache"] {
    let required: Set<String> = ["host", "download_status_flags", flag]
    precondition(SafariCacheLayout(columns: required)?.flag == flag)
    precondition(SafariCacheLayout(columns: required)?.hasDisplay == false)
    precondition(SafariCacheLayout(columns: required.union(["transparency_analysis_result"]))?.hasDisplay == true)
    precondition(SafariCacheLayout(columns: required.subtracting(["host"])) == nil)
    precondition(SafariCacheLayout(columns: required.subtracting(["download_status_flags"])) == nil)
}
precondition(SafariCacheLayout(columns: ["host","download_status_flags","touch_icon_is_in_cache","icon_is_in_cache"]) == nil)
precondition(SafariCacheLayout(columns: ["host","download_status_flags","future_flag"]) == nil)
print("OK: durable journal, restart, lock, invalid marker and symlink rejection, four known layouts and unknown/ambiguous schema rejection")
