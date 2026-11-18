import Foundation

// Portable, versioned data only. No paths, URLs, bookmark titles or executable content.
struct IconCollection: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        let host: String
        let png: Data
        let display: SafariIconDisplay?
        var id: String { host }
    }
    let format: Int
    let icons: [Entry]
    static let maximumBytes = 64_000_000
    static let maximumEntries = 500
    static let maximumPNGBytes = 8_000_000

    static func validHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= 253, host == host.lowercased(), !host.hasPrefix("."), !host.hasSuffix(".") else { return false }
        return host.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }
            && host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") }
    }
    // Cheap preflight before platform image decoding. Actual PNG decoding is mandatory in the UI.
    static func validPNGHeader(_ data: Data) -> Bool {
        guard data.count >= 33, data.count <= maximumPNGBytes else { return false }
        let b = Array(data.prefix(24))
        guard Array(b[0..<16]) == [137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82] else { return false }
        func dimension(_ start: Int) -> Int { b[start..<start+4].reduce(0) { ($0 << 8) | Int($1) } }
        return (1...1024).contains(dimension(16)) && (1...1024).contains(dimension(20))
    }
    func validated() throws -> IconCollection {
        guard format == 1, !icons.isEmpty, icons.count <= Self.maximumEntries,
              Set(icons.map(\.host)).count == icons.count,
              icons.allSatisfy({ Self.validHost($0.host) && Self.validPNGHeader($0.png) }),
              icons.reduce(0, { $0 + $1.png.count }) <= 45_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        return self
    }
    static func decode(_ data: Data) throws -> IconCollection {
        guard data.count <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }
    func encoded() throws -> Data {
        _ = try validated()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        return data
    }
    func matching(allowed: Set<String>, alreadyPrepared: Set<String>) -> [Entry] {
        icons.filter { allowed.contains($0.host) && !alreadyPrepared.contains($0.host) }
    }
}
