import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// The marker refers only to a completed, durable, immutable local snapshot.
// No arbitrary paths are decoded from disk. A lock excludes concurrent writers.
struct RecoveryJournal {
    struct Record: Codable, Equatable {
        let format: Int
        let snapshot: UUID
    }
    let root: URL
    var marker: URL { root.appendingPathComponent("RecoveryJournal.json") }
    private let fm = FileManager.default
    static func directory(_ url: URL) throws {
        let v = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard v.isDirectory == true, v.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
    }
    static func regular(_ url: URL) throws {
        let v = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard v.isRegularFile == true, v.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
    }
    static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }
    static func sync(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
    static func syncTree(_ url: URL) throws {
        let v = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard v.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
        if v.isDirectory == true {
            for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) { try syncTree(child) }
        } else if v.isRegularFile != true { throw CocoaError(.fileReadCorruptFile) }
        try sync(url)
    }
    func withLock<T>(_ body: () throws -> T) throws -> T {
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Self.directory(root)
        let fd = open(root.appendingPathComponent("Recovery.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
    func read() throws -> Record? {
        guard Self.exists(root) else { return nil }
        try Self.directory(root)
        guard Self.exists(marker) else { return nil }
        try Self.regular(marker)
        guard (try marker.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 4096 else { throw CocoaError(.fileReadCorruptFile) }
        let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: marker))
        guard record.format == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return record
    }
    func begin(snapshot: URL) throws {
        guard try read() == nil, let id = UUID(uuidString: snapshot.lastPathComponent),
              snapshot.lastPathComponent == id.uuidString,
              snapshot.deletingLastPathComponent().standardizedFileURL.path == root.appendingPathComponent("Backups").standardizedFileURL.path else { throw CocoaError(.fileWriteInvalidFileName) }
        try Self.directory(snapshot.deletingLastPathComponent())
        try Self.syncTree(snapshot)
        try Self.sync(snapshot.deletingLastPathComponent())
        let temp = root.appendingPathComponent(".journal-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temp) }
        let bytes = try JSONEncoder().encode(Record(format: 1, snapshot: id))
        guard fm.createFile(atPath: temp.path, contents: bytes, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        try Self.sync(temp)
        try fm.moveItem(at: temp, to: marker)
        try Self.sync(root)
    }
    func snapshot(_ record: Record) -> URL { root.appendingPathComponent("Backups").appendingPathComponent(record.snapshot.uuidString) }
    func finish() throws {
        try fm.removeItem(at: marker)
        try Self.sync(root)
    }
}

// Known column layouts, never guessed version numbers. Unknown or ambiguous layouts fail closed.
struct SafariCacheLayout: Equatable {
    let flag: String
    let hasDisplay: Bool
    init?(columns: Set<String>) {
        let flags = ["touch_icon_is_in_cache", "icon_is_in_cache"].filter { columns.contains($0) }
        guard columns.contains("host"), columns.contains("download_status_flags"), flags.count == 1 else { return nil }
        flag = flags[0]; hasDisplay = columns.contains("transparency_analysis_result")
    }
}
