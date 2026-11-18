import Foundation

struct ReleaseVersion: Comparable, Equatable {
    let major: Int, minor: Int, patch: Int
    init?(_ tag: String) {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } && ($0.count == 1 || $0.first != "0") }),
              let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]) else { return nil }
        major = a; minor = b; patch = c
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
    var string: String { "\(major).\(minor).\(patch)" }
}

struct GitHubRelease: Decodable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let body: String?
    let assets: [Asset]
    struct Asset: Decodable { let name: String }
    enum CodingKeys: String, CodingKey { case tagName = "tag_name", draft, prerelease, body, assets }
    var version: ReleaseVersion? { guard !draft, !prerelease else { return nil }; return ReleaseVersion(tagName) }
    func macAsset(architecture: String) -> String? {
        let name = "SafariIconFixer-\(version?.string ?? "")-macOS-\(architecture).zip"
        return assets.contains(where: { $0.name == name }) ? name : nil
    }
}
