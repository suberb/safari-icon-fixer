import Foundation
let fm = FileManager.default
let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: temp, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: temp) }
func make(_ offset: TimeInterval) throws -> URL {
    let dir = temp.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: dir.appendingPathComponent("Images"), withIntermediateDirectories: true)
    try Data(repeating: 1, count: 9).write(to: dir.appendingPathComponent("TouchIconCacheSettings.db"))
    try Data(repeating: 2, count: 11).write(to: dir.appendingPathComponent("Images/test.png"))
    try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: offset)], ofItemAtPath: dir.path)
    return dir
}
let older = try make(100), newest = try make(200)
let decoy = temp.appendingPathComponent(UUID().uuidString)
try fm.createSymbolicLink(at: decoy, withDestinationURL: older)
try fm.createSymbolicLink(at: older.appendingPathComponent("Images/unrelated"), withDestinationURL: newest)
let entries = try BackupInventory.list(temp)
precondition(entries.map(\.id) == [newest.lastPathComponent, older.lastPathComponent])
precondition(entries.allSatisfy { $0.bytes == 20 })
let removable = try BackupInventory.removable(temp, id: older.lastPathComponent)
// macOS temp paths can be spelled /var or /private/var (same directory).
precondition(removable.resolvingSymlinksInPath().standardizedFileURL.path == older.resolvingSymlinksInPath().standardizedFileURL.path)
precondition(removable.lastPathComponent == older.lastPathComponent)
precondition(removable.resolvingSymlinksInPath().path != newest.resolvingSymlinksInPath().path)
for id in [newest.lastPathComponent, decoy.lastPathComponent, "../outside"] {
    do { _ = try BackupInventory.removable(temp, id: id); fatalError("unsafe deletion") } catch {}
}
try fm.removeItem(at: older)
do { _ = try BackupInventory.removable(temp, id: newest.lastPathComponent); fatalError("last backup") } catch {}
print("OK: inventory, logical bytes, symlink exclusion, newest and final backup protection")
