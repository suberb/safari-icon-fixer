import Foundation

enum FavoriteScope: Hashable {
    case all, root, folder([String])
    func includes(_ path: [String]) -> Bool {
        switch self {
        case .all: return true
        case .root: return path.isEmpty
        case .folder(let prefix): return path.starts(with: prefix)
        }
    }
}
struct FavoriteFolder: Identifiable {
    let path: [String]
    let titles: [String]
    var id: [String] { path }
    var label: String { titles.joined(separator: " / ") }
    var scope: FavoriteScope { .folder(path) }
}
struct FavoriteLink {
    let host: String
    let title: String
    let folder: [String]
    let folderTitles: [String]
}
struct FavoritesIndex {
    let links: [FavoriteLink]
    let folders: [FavoriteFolder]
    enum ReadError: LocalizedError {
        case unknownFavorites
        var errorDescription: String? { l10n("Nie rozpoznano standardowego folderu Ulubione (BookmarksBar). Nie zmieniono plików.") }
    }
    init(root: [String: Any]) throws {
        func children(_ node: [String: Any]) -> [[String: Any]] { node["Children"] as? [[String: Any]] ?? [] }
        let roots = children(root).filter { ($0["Title"] as? String) == "BookmarksBar" && $0["Children"] is [[String: Any]] }
        guard roots.count == 1, let favorites = roots.first else { throw ReadError.unknownFavorites }
        var links: [FavoriteLink] = []; var folders: [FavoriteFolder] = []
        func visit(_ nodes: [[String: Any]], path: [String], titles: [String]) {
            for (index, node) in nodes.enumerated() {
                if let raw = node["URLString"] as? String, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host?.lowercased(), !host.isEmpty {
                    let name = (node["URIDictionary"] as? [String: Any])?["title"] as? String ?? host
                    links.append(FavoriteLink(host: host, title: name, folder: path, folderTitles: titles))
                } else if let entries = node["Children"] as? [[String: Any]] {
                    // UUID is stable if Safari supplies it; otherwise the position distinguishes identical names.
                    let segment = (node["WebBookmarkUUID"] as? String).map { "uuid:" + $0 } ?? "index:\(index):\(node["Title"] as? String ?? "")"
                    let newPath = path + [segment]
                    let newTitles = titles + [node["Title"] as? String ?? l10n("Folder bez nazwy")]
                    folders.append(FavoriteFolder(path: newPath, titles: newTitles))
                    visit(entries, path: newPath, titles: newTitles)
                }
            }
        }
        visit(children(favorites), path: [], titles: [])
        self.links = links; self.folders = folders
    }
    func hosts(in scope: FavoriteScope) -> Set<String> { Set(links.filter { scope.includes($0.folder) }.map(\.host)) }
}
