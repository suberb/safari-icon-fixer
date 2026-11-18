import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// Stored independently of Safari. No bookmarks, URLs or network operations.
struct ProtectedIcon: Codable, Equatable {
    let png: Data
    let display: SafariIconDisplay?
}
struct PersonalizationState: Codable, Equatable {
    var registry: [String: String] = [:]
    var icons: [String: ProtectedIcon] = [:]

    mutating func remember(host: String, png: Data, digest: String, display: SafariIconDisplay?) {
        registry[host] = digest
        icons[host] = ProtectedIcon(png: png, display: display)
    }
    mutating func forget(_ host: String) {
        registry.removeValue(forKey: host)
        icons.removeValue(forKey: host)
    }
    func needsRecovery(host: String, current: Data?, displayCode: Int?) -> Bool {
        guard let saved = icons[host] else { return false }
        return current != saved.png || (saved.display != nil && saved.display?.rawValue != displayCode)
    }
}

// Single atomic file for matching digests and artwork; backups contain this same format.
struct PersonalizationFile {
    static let limit = 160_000_000
    static func read(_ url: URL) throws -> PersonalizationState {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= limit else { throw CocoaError(.fileReadCorruptFile) }
        let value = try JSONDecoder().decode(PersonalizationState.self, from: Data(contentsOf: url))
        guard value.icons.allSatisfy({ value.registry[$0.key] != nil && !$0.value.png.isEmpty && $0.value.png.count <= 8_000_000 }) else { throw CocoaError(.fileReadCorruptFile) }
        return value
    }
    static func write(_ value: PersonalizationState, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= limit else { throw CocoaError(.fileWriteOutOfSpace) }
        // Atomic replacement; do not follow symlinks or change unrelated files.
        if let info = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]) {
            guard info.isSymbolicLink != true, info.isRegularFile == true else { throw CocoaError(.fileWriteInvalidFileName) }
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Write into a private directory; create the file with private permissions before rename.
        let temp = url.deletingLastPathComponent().appendingPathComponent(".sif-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        defer { try? FileManager.default.removeItem(at: temp) }
        guard rename(temp.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
