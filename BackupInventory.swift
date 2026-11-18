import Foundation

struct BackupEntry: Identifiable, Equatable {
    let url: URL
    let date: Date
    let bytes: Int64?
    var id: String { url.lastPathComponent }
}

enum BackupInventory {
    private static let fm = FileManager.default
    private static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]
    private static func candidates(_ root: URL) throws -> [BackupEntry] {
        guard fm.fileExists(atPath: root.path) else { return [] }
        let rootInfo = try root.resourceValues(forKeys: keys)
        guard rootInfo.isDirectory == true, rootInfo.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
        return try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]).compactMap { url -> BackupEntry? in
            guard UUID(uuidString: url.lastPathComponent) != nil,
                let info = try? url.resourceValues(forKeys: keys), info.isDirectory == true, info.isSymbolicLink != true,
                let db = try? url.appendingPathComponent("TouchIconCacheSettings.db").resourceValues(forKeys: keys), db.isRegularFile == true, db.isSymbolicLink != true,
                let images = try? url.appendingPathComponent("Images").resourceValues(forKeys: keys), images.isDirectory == true, images.isSymbolicLink != true else { return nil }
            // Modification date is refreshed after a complete snapshot in Cache.backup.
            return BackupEntry(url: url, date: info.contentModificationDate ?? info.creationDate ?? .distantPast, bytes: nil)
        }.sorted { a, b in a.date == b.date ? a.id < b.id : a.date > b.date }
    }
    static func list(_ root: URL) throws -> [BackupEntry] {
        try candidates(root).map { entry in
            try Task.checkCancellation()
            var complete = true
            var total: Int64 = 0
            guard let items = fm.enumerator(at: entry.url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in complete = false; return true }) else { return entry }
            for case let item as URL in items {
                try Task.checkCancellation()
                guard let info = try? item.resourceValues(forKeys: keys) else { complete = false; items.skipDescendants(); continue }
                if info.isSymbolicLink == true { items.skipDescendants(); continue }
                if info.isRegularFile == true, let size = info.fileSize, size >= 0 {
                    let sum = total.addingReportingOverflow(Int64(size))
                    if sum.overflow { complete = false } else { total = sum.partialValue }
                }
            }
            return BackupEntry(url: entry.url, date: entry.date, bytes: complete ? total : nil)
        }
    }
    // Validate again immediately before moving to Trash; never delete the newest valid snapshot.
    static func removable(_ root: URL, id: String) throws -> URL {
        let fresh = try candidates(root)
        guard fresh.count > 1, fresh.first?.id != id, let match = fresh.first(where: { $0.id == id }) else { throw CocoaError(.fileWriteNoPermission) }
        return match.url
    }
}
