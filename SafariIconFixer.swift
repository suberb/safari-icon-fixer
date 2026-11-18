import SwiftUI
import Combine
import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import QuickLook

struct FixError: LocalizedError { let message: String; var errorDescription: String? { message } }
func fail(_ s: String) -> FixError { FixError(message: s) }
struct Site: Identifiable {
    var id: String { host }; let host: String; var names: [String]; let locations: [FavoriteLink]; let registered: Bool; let existing: Data?; let active: Bool; let downloadFlags: Int?; let pixelSize: Int?; let displayCode: Int?
    var title: String { names.joined(separator: " · ") }
    var needsRepair: Bool { !registered || existing == nil || !active || downloadFlags != 1 }
    var status: String {
        if !registered { return l10n("Brak rekordu") }
        if existing == nil { return l10n("Brak ikony") }
        if !active { return l10n("Ikona nieaktywna") }
        if downloadFlags != 1 { return l10n("Status do sprawdzenia") }
        return l10n("W cache") // This is not proof of rendering in Safari.
    }
}
struct Pending: Codable, Equatable {
    let png: Data; let source: String; let custom: Bool; let display: SafariIconDisplay?; let expectedDigest: String?
    init(png: Data, source: String, custom: Bool = false, display: SafariIconDisplay? = nil, expectedDigest: String? = nil) { self.png = png; self.source = source; self.custom = custom; self.display = display; self.expectedDigest = expectedDigest }
}
func iconDigest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

func hash(_ host: String) -> String { Insecure.MD5.hash(data: Data(host.utf8)).map { String(format: "%02X", $0) }.joined() }
func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "''") + "'" }
func sql(_ db: URL, _ query: String, write: Bool = false) throws -> Data {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    p.arguments = ["-bail", "-init", "/dev/null"] + (write ? [] : ["-readonly", "-json"]) + [db.path, ".timeout 3000", query]
    let output = Pipe(); let error = Pipe(); p.standardOutput = output; p.standardError = error
    try p.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); let err = error.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw fail(String(data: err, encoding: .utf8) ?? l10n("Błąd SQLite")) }; return data
}
func rows(_ db: URL, _ query: String) throws -> [[String: Any]] {
    let data = try sql(db, query); if data.isEmpty { return [] }
    guard let result = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw fail(l10n("Nierozpoznany wynik SQLite.")) }; return result
}
private func cachedIconSource(_ data: Data) -> (CGImageSource, Int, Int)? {
    guard data.count <= 8_000_000, let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    var best = 0; var score = 0
    for i in 0..<min(CGImageSourceGetCount(src), 32) {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [String: Any], let w = props[kCGImagePropertyPixelWidth as String] as? Int, let h = props[kCGImagePropertyPixelHeight as String] as? Int, w > 0, h > 0, w <= 8192, h <= 8192 else { continue }
        if min(w,h) > score { score = min(w,h); best = i }
    }
    guard score > 0 else { return nil }
    return (src, best, score)
}
func cachedIconSize(_ data: Data) -> Int? {
    guard let (src, best, score) = cachedIconSource(data),
          CGImageSourceCreateThumbnailAtIndex(src, best, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 64, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil else { return nil }
    return score
}
func safePNG(_ data: Data) -> (Data, Int)? {
    guard let (src, best, score) = cachedIconSource(data), let image = CGImageSourceCreateThumbnailAtIndex(src, best, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary), let ctx = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let scale = 256 / CGFloat(max(image.width, image.height)); let w = CGFloat(image.width)*scale, h = CGFloat(image.height)*scale
    ctx.interpolationQuality = .high; ctx.draw(image, in: CGRect(x: (256-w)/2, y: (256-h)/2, width: w, height: h))
    guard let rendered = ctx.makeImage() else { return nil }; let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }; CGImageDestinationAddImage(dest, rendered, nil); guard CGImageDestinationFinalize(dest) else { return nil }; return (out as Data, score)
}

struct HistoricalIcon: Identifiable {
    let id: String
    let date: Date
    let png: Data
    let style: SafariIconDisplay?
}
struct Cache {
    static let fm = FileManager.default
    let safari: URL
    var cache: URL { safari.appendingPathComponent("Touch Icons Cache", isDirectory: true) }
    var db: URL { cache.appendingPathComponent("TouchIconCacheSettings.db") }
    var images: URL { cache.appendingPathComponent("Images", isDirectory: true) }
    var backups: URL { Cache.fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Safari Icon Fixer/Backups", isDirectory: true) }
    var registryURL: URL { backups.deletingLastPathComponent().appendingPathComponent("CustomIcons.json") }
    var personalizationURL: URL { backups.deletingLastPathComponent().appendingPathComponent("Personalization.json") }
    private let snapshotMetadata = "SIF-Personalization.json"
    var draftURL: URL { backups.deletingLastPathComponent().appendingPathComponent("PreparedIcons.json") }
    func readDraft() throws -> [String: Pending] {
        guard Cache.fm.fileExists(atPath: draftURL.path) else { return [:] }
        let info = try draftURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) <= 160_000_000 else { throw fail(l10n("Nie można odczytać przygotowanych ikon.")) }
        return try JSONDecoder().decode([String: Pending].self, from: Data(contentsOf: draftURL))
    }
    func saveDraft(_ items: [String: Pending]) throws {
        if items.isEmpty {
            if Cache.fm.fileExists(atPath: draftURL.path) { try Cache.fm.removeItem(at: draftURL) }
            return
        }
        try Cache.fm.createDirectory(at: draftURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(items)
        guard data.count <= 160_000_000 else { throw fail(l10n("Nie można zapisać przygotowanych ikon.")) }
        try data.write(to: draftURL, options: .atomic)
        try Cache.fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: draftURL.path)
    }
    func history(for host: String) throws -> [HistoricalIcon] {
        guard Cache.fm.fileExists(atPath: backups.path) else { return [] }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey, .contentModificationDateKey]
        let directories = try Cache.fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        let candidates = directories.compactMap { path -> (URL, Date)? in
            guard UUID(uuidString: path.lastPathComponent) != nil, let info = try? path.resourceValues(forKeys: keys), info.isDirectory == true, info.isSymbolicLink != true else { return nil }
            return (path, info.creationDate ?? info.contentModificationDate ?? .distantPast)
        }.sorted { $0.1 > $1.1 }
        var result: [HistoricalIcon] = []
        var seen = Set<String>()
        for (directory, date) in candidates.prefix(40) {
            let imageDir = directory.appendingPathComponent("Images", isDirectory: true)
            guard (try? imageDir.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { continue }
            let file = imageDir.appendingPathComponent(hash(host) + ".png")
            guard let info = try? file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]), info.isSymbolicLink != true, info.isRegularFile == true, (info.fileSize ?? Int.max) <= 8_000_000,
                  let data = try? Data(contentsOf: file), safePNG(data) != nil else { continue }
            let oldDB = directory.appendingPathComponent("TouchIconCacheSettings.db")
            var display: SafariIconDisplay?
            if let dbInfo = try? oldDB.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]), dbInfo.isRegularFile == true, dbInfo.isSymbolicLink != true,
               let oldRows = try? rows(oldDB, "SELECT transparency_analysis_result AS style FROM cache_settings WHERE host=\(quote(host));"), oldRows.count == 1,
               let code = oldRows.first?["style"] as? Int { display = SafariIconDisplay(rawValue: code) }
            let digest = iconDigest(data) + ":" + String(display?.rawValue ?? -1)
            guard seen.insert(digest).inserted else { continue }
            result.append(HistoricalIcon(id: digest, date: date, png: data, style: display))
        }
        return result
    }
    func personalization() throws -> PersonalizationState {
        // Legacy digest-only registry is never overwritten by migration.
        if Cache.fm.fileExists(atPath: personalizationURL.path) { return try PersonalizationFile.read(personalizationURL) }
        guard Cache.fm.fileExists(atPath: registryURL.path) else { return PersonalizationState() }
        let info = try registryURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) <= PersonalizationFile.limit else { throw CocoaError(.fileReadCorruptFile) }
        return PersonalizationState(registry: try JSONDecoder().decode([String: String].self, from: Data(contentsOf: registryURL)))
    }
    func savePersonalization(_ value: PersonalizationState) throws {
        try PersonalizationFile.write(value, to: personalizationURL)
    }
    func captureKnownIcons(_ sites: [Site]) throws -> PersonalizationState {
        let old = try personalization()
        var current = old
        for site in sites where site.registered {
            // Import only a verified, previously customized image, never guess from an overwritten icon.
            guard current.icons[site.host] == nil, let data = site.existing,
                  let digest = current.registry[site.host], iconDigest(data) == digest else { continue }
            current.remember(host: site.host, png: data, digest: digest, display: site.displayCode.flatMap(SafariIconDisplay.init(rawValue:)))
        }
        if current != old { try savePersonalization(current) }
        return current
    }
    var safariRunning: Bool { NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Safari" || $0.bundleIdentifier == "com.apple.SafariTechnologyPreview" } }
    func icon(_ host: String) -> URL { images.appendingPathComponent(hash(host) + ".png") }
    func schema() throws -> String {
        for path in [safari, cache, images, db] {
            let v = try path.resourceValues(forKeys: [.isSymbolicLinkKey]); guard v.isSymbolicLink != true else { throw fail(l10n("Nieobsługiwana ścieżka symboliczna: {0}", String(describing: path.path))) }
        }
        let cols = Set(try rows(db,"PRAGMA table_info(cache_settings);").compactMap { $0["name"] as? String })
        guard cols.contains("host"), cols.contains("download_status_flags"), let flag = ["touch_icon_is_in_cache", "icon_is_in_cache"].first(where: {cols.contains($0)}) else { throw fail(l10n("Nieznany schemat cache Safari. Zapis jest zablokowany.")) }
        return flag
    }
    func hasDisplayColumn() throws -> Bool {
        let cols = try rows(db, "PRAGMA table_info(cache_settings);")
        return cols.contains { ($0["name"] as? String) == "transparency_analysis_result" }
    }
    // Probe the actual Safari files, not a guessed TCC authorization flag.
    // Read-only: no test writes to the user's cache.
    func checkReadAccess() throws {
        _ = try Cache.fm.contentsOfDirectory(atPath: safari.path)
        for file in [safari.appendingPathComponent("Bookmarks.plist"), db] {
            let handle = try FileHandle(forReadingFrom: file)
            try handle.close()
        }
        _ = try Cache.fm.contentsOfDirectory(atPath: images.path)
    }
    func scan() throws -> (sites: [Site], folders: [FavoriteFolder]) {
        try checkReadAccess()
        let flag = try schema(); let bookmark = safari.appendingPathComponent("Bookmarks.plist")
        let obj = try PropertyListSerialization.propertyList(from: Data(contentsOf: bookmark), options: [], format: nil)
        guard let root = obj as? [String: Any] else { throw fail(l10n("Nieznany format zakładek.")) }
        let index = try FavoritesIndex(root: root)
        let named = Dictionary(grouping: index.links, by: \.host)
        let displayExpr = try hasDisplayColumn() ? "transparency_analysis_result" : "NULL"
        let dbRows = try rows(db, "SELECT host, \(flag) AS active, download_status_flags AS download_flags, \(displayExpr) AS display_code FROM cache_settings;")
        var displayCodes: [String: Int] = [:]
        var registered: [String: [Int]] = [:]
        var downloadFlags: [String: Int] = [:]
        for row in dbRows {
            if let h = row["host"] as? String {
                registered[h,default: []].append(row["active"] as? Int ?? 0)
                downloadFlags[h] = row["download_flags"] as? Int
                displayCodes[h] = row["display_code"] as? Int
            }
        }
        var sites: [Site] = []
        for (host, links) in named {
            try Task.checkCancellation()
            let url: URL = icon(host)
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            var existing: Data? = nil
            var pixelSize: Int? = nil
            if let values, values.isSymbolicLink != true, values.isRegularFile == true, (values.fileSize ?? Int.max) <= 8_000_000 {
                if let data = try? Data(contentsOf: url), let size = cachedIconSize(data) {
                    existing = data
                    pixelSize = size
                }
            }
            let titles: [String] = links.map { link in link.title }
            let names: [String] = Set(titles).sorted()
            let flags: [Int] = registered[host] ?? []
            let isRegistered: Bool = flags.count == 1
            let isActive: Bool = flags.first == 1
            let site = Site(host: host, names: names, locations: links,
                            registered: isRegistered, existing: existing, active: isActive,
                            downloadFlags: downloadFlags[host], pixelSize: pixelSize, displayCode: displayCodes[host])
            sites.append(site)
        }
        sites.sort { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return (sites, index.folders)
    }
    func backup(_ personalization: PersonalizationState) throws -> URL {
        guard !safariRunning else { throw fail(l10n("Zamknij Safari (⌘Q), a następnie ponów.")) }
        try Cache.fm.createDirectory(at: backups, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let dest = backups.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try Cache.fm.copyItem(at: cache, to: dest)
            try PersonalizationFile.write(personalization, to: dest.appendingPathComponent(snapshotMetadata))
        } catch {
            // An incomplete snapshot is never offered as a valid backup.
            try? Cache.fm.removeItem(at: dest); throw error
        }
        let now = Date(); try? Cache.fm.setAttributes([.creationDate: now, .modificationDate: now], ofItemAtPath: dest.path)
        return dest
    }
    func apply(_ pending: [String: Pending], allowingReplacement: Set<String>, scope: FavoriteScope) throws -> (URL, Int) {
        guard !pending.isEmpty, !safariRunning else { throw fail(l10n("Zamknij Safari (⌘Q) i przygotuj ikony.")) }
        let flag = try schema(); let current = try scan().sites; let byHost = Dictionary(uniqueKeysWithValues: current.map { ($0.host, $0) })
        for (host, item) in pending {
            guard let site = byHost[host], site.locations.contains(where: { scope.includes($0.folder) }), site.registered, site.existing == nil || allowingReplacement.contains(host) || (site.needsRepair && site.existing == item.png) else { throw fail(l10n("Stan {0} uległ zmianie lub rekord nie istnieje. Przeskanuj ponownie.", String(describing: host))) }
            if let expected = item.expectedDigest, site.existing.map(iconDigest) != expected { throw fail(l10n("Ikona {0} zmieniła się od przygotowania. Przeskanuj i ponów.", String(describing: host))) }
            if Cache.fm.fileExists(atPath: icon(host).path), try icon(host).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw fail(l10n("Odmowa zapisu do dowiązania symbolicznego.")) }
        }
        guard current.contains(where: { $0.registered && $0.existing != nil && $0.active }) else { throw fail(l10n("Nie potwierdzono mapowania nazw plików MD5 dla tej wersji Safari. Zapis zablokowany.")) }
        let supportsDisplay = try hasDisplayColumn()
        if !supportsDisplay && pending.values.contains(where: { $0.display != nil }) {
            throw fail(l10n("Ta wersja cache Safari nie udostępnia parametru stylu ikon. Nie zapisano zmian."))
        }
        let oldState = try personalization()
        var nextState = oldState
        for (host, item) in pending {
            let currentDigest = byHost[host]?.existing.map(iconDigest)
            let knownDigest = oldState.registry[host]
            if item.custom || (currentDigest != nil && currentDigest == knownDigest) {
                let style = item.display ?? byHost[host]?.displayCode.flatMap(SafariIconDisplay.init(rawValue:))
                nextState.remember(host: host, png: item.png, digest: iconDigest(item.png), display: style)
            }
            // A generic repair must not erase the protected version of an overwritten icon.
        }
        let saved = try backup(oldState); var changed: [String] = []; var registryChanged = false
        do {
            guard !safariRunning else { throw fail(l10n("Safari zostało otwarte podczas przygotowania.")) }
            for (host, item) in pending {
                guard !safariRunning else { throw fail(l10n("Safari zostało otwarte podczas zapisu.")) }
                if byHost[host]?.existing != item.png { changed.append(host); try item.png.write(to: icon(host), options: .atomic) }
            }
            guard !safariRunning else { throw fail(l10n("Safari zostało otwarte podczas zapisu.")) }
            if oldState != nextState { try savePersonalization(nextState); registryChanged = true }
            guard !safariRunning else { throw fail(l10n("Safari zostało otwarte podczas zapisu.")) }
            let statements = pending.keys.sorted().map { host -> String in
                let assignment = iconDisplayAssignment(pending[host]?.display)
                return "UPDATE cache_settings SET \(flag)=1, download_status_flags=1\(assignment) WHERE host=\(quote(host));"
            }.joined(separator: "\n")
            _ = try sql(db, "BEGIN IMMEDIATE;\n" + statements + "\nCOMMIT;", write: true)
            return (saved, pending.count)
        } catch {
            var problems: [String] = []
            if registryChanged { do { try savePersonalization(oldState) } catch { problems.append(l10n("rejestr własnych ikon")) } }
            for host in changed {
                let before = saved.appendingPathComponent("Images").appendingPathComponent(hash(host)+".png")
                do { if Cache.fm.fileExists(atPath: before.path) { try Data(contentsOf: before).write(to: icon(host), options: .atomic) } else if Cache.fm.fileExists(atPath: icon(host).path) { try Cache.fm.removeItem(at: icon(host)) } } catch { problems.append(host) }
            }
            throw fail(l10n("Zapis przerwany: {0}. Kopia: {1}", String(describing: error.localizedDescription), String(describing: saved.path)) + (problems.isEmpty ? "" : l10n(" Nie udało się odtworzyć: {0}", String(describing: problems.joined(separator: ", ")))))
        }
    }
    func reset(_ hosts: Set<String>, scope: FavoriteScope, trackedOnly: Bool) throws -> URL {
        guard !hosts.isEmpty, !safariRunning else { throw fail(l10n("Zamknij Safari (⌘Q), a następnie ponów reset.")) }
        let flag = try schema()
        let sites = try scan().sites
        let byHost = Dictionary(uniqueKeysWithValues: sites.map { ($0.host, $0) })
        let oldState = try personalization()
        var nextState = oldState
        // Never touch domains outside the requested scope or unknown/ambiguous rows.
        for host in hosts {
            guard let site = byHost[host], site.registered, site.locations.contains(where: { scope.includes($0.folder) }) else { throw fail(l10n("Stan {0} zmienił się. Przeskanuj ponownie.", String(describing: host))) }
            if trackedOnly {
                guard let data = site.existing, oldState.registry[host] == iconDigest(data) else { throw fail(l10n("Ikona {0} została zmieniona poza aplikacją. Przeskanuj ponownie.", String(describing: host))) }
            }
            let path = icon(host)
            if let values = try? path.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]) {
                guard values.isSymbolicLink != true, values.isRegularFile == true else { throw fail(l10n("Nieprawidłowa ścieżka ikony: {0}.", String(describing: host))) }
            } else if Cache.fm.fileExists(atPath: path.path) { throw fail(l10n("Nie można zweryfikować pliku: {0}.", String(describing: host))) }
            nextState.forget(host)
        }
        guard sites.contains(where: { $0.registered && $0.existing != nil && $0.active }) else { throw fail(l10n("Nie potwierdzono mapowania cache dla tej wersji Safari.")) }
        let saved = try backup(oldState)
        var removed: [String] = []; var registryChanged = false
        do {
            for host in hosts.sorted() {
                guard !safariRunning else { throw fail(l10n("Safari zostało otwarte podczas resetu.")) }
                let path = icon(host)
                if Cache.fm.fileExists(atPath: path.path) { try Cache.fm.removeItem(at: path); removed.append(host) }
            }
            if nextState != oldState { try savePersonalization(nextState); registryChanged = true }
            guard !safariRunning else { throw fail(l10n("Safari zostało otwarte podczas resetu.")) }
            let statements = hosts.sorted().map { "UPDATE cache_settings SET \(flag)=0, download_status_flags=0 WHERE host=\(quote($0));" }.joined(separator: "\n")
            _ = try sql(db, "BEGIN IMMEDIATE;\n" + statements + "\nCOMMIT;", write: true)
            return saved
        } catch {
            var problems: [String] = []
            if registryChanged { do { try savePersonalization(oldState) } catch { problems.append(l10n("rejestr własnych ikon")) } }
            for host in removed {
                let file = saved.appendingPathComponent("Images").appendingPathComponent(hash(host)+".png")
                do { try Data(contentsOf: file).write(to: icon(host), options: .atomic) } catch { problems.append(host) }
            }
            throw fail(l10n("Reset przerwany: {0}. Kopia: {1}", String(describing: error.localizedDescription), String(describing: saved.path)) + (problems.isEmpty ? "" : l10n(" Nie odtworzono: ") + problems.joined(separator: ", ")))
        }
    }
    func restore(_ saved: URL) throws -> URL {
        _ = try schema()
        guard !safariRunning else { throw fail(l10n("Zamknij Safari (⌘Q).")) }
        guard saved.deletingLastPathComponent().standardizedFileURL == backups.standardizedFileURL, UUID(uuidString: saved.lastPathComponent) != nil, Cache.fm.fileExists(atPath: saved.appendingPathComponent("TouchIconCacheSettings.db").path) else { throw fail(l10n("Wybierz prawidłową kopię aplikacji.")) }
        guard !safariRunning else { throw fail(l10n("Zamknij Safari.")) }
        let oldState = try personalization()
        let info = try saved.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw fail(l10n("Wybierz prawidłową kopię aplikacji.")) }
        let backupDB = try saved.appendingPathComponent("TouchIconCacheSettings.db").resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let backupImages = try saved.appendingPathComponent("Images").resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard backupDB.isRegularFile == true, backupDB.isSymbolicLink != true, backupImages.isDirectory == true, backupImages.isSymbolicLink != true else { throw fail(l10n("Wybierz prawidłową kopię aplikacji.")) }
        let metadata = saved.appendingPathComponent(snapshotMetadata)
        // Old backups have no metadata. Keep the protected collection instead of inventing a historical registry.
        let hasMetadata = Cache.fm.fileExists(atPath: metadata.path)
        let restoredState = hasMetadata ? try PersonalizationFile.read(metadata) : oldState
        let staged = safari.appendingPathComponent("SIF-stage-\(UUID().uuidString)")
        let displaced = backups.appendingPathComponent(UUID().uuidString)
        defer { try? Cache.fm.removeItem(at: staged) }
        try Cache.fm.copyItem(at: saved, to: staged)
        if hasMetadata { try Cache.fm.removeItem(at: staged.appendingPathComponent(snapshotMetadata)) }
        guard !safariRunning else { throw fail(l10n("Safari zostało otwarte.")) }
        try Cache.fm.moveItem(at: cache, to: displaced)
        var installed = false
        do {
            try PersonalizationFile.write(oldState, to: displaced.appendingPathComponent(snapshotMetadata))
            guard !safariRunning else { throw fail(l10n("Safari zostało otwarte.")) }
            try Cache.fm.moveItem(at: staged, to: cache); installed = true
            if restoredState != oldState { try savePersonalization(restoredState) }
        } catch {
            do {
                if installed { try Cache.fm.moveItem(at: cache, to: staged) }
                let sidecar = displaced.appendingPathComponent(snapshotMetadata)
                if Cache.fm.fileExists(atPath: sidecar.path) { try Cache.fm.removeItem(at: sidecar) }
                try Cache.fm.moveItem(at: displaced, to: cache)
            } catch { throw fail(l10n("Nie udało się odtworzyć bieżącej pamięci. Zachowano ją w {0}.", String(describing: displaced.path))) }
            throw error
        }
        return displaced
    }
}

final class SameHost: NSObject, URLSessionTaskDelegate {
    let host: String; init(_ host: String) { self.host = host }
    func accepts(_ url: URL) -> Bool { guard url.scheme == "https", let h = url.host?.lowercased(), url.user == nil, url.password == nil else { return false }; return h == host || h == "www." + host || (host.hasPrefix("www.") && h == String(host.dropFirst(4))) }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(request.url.map(accepts) == true ? request : nil) }
}
func fetchWebsiteIcons(_ host: String, multiple: Bool = false) async -> [IconCandidate] {
    guard let root = URL(string: "https://\(host)/") else { return [] }
    let policy = SameHost(host); let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 6; config.timeoutIntervalForResource = 10; config.httpShouldSetCookies = false; config.urlCredentialStorage = nil
    let session = URLSession(configuration: config, delegate: policy, delegateQueue: nil); defer { session.invalidateAndCancel() }
    func get(_ url: URL, limit: Int) async -> (Data,URL)? {
        guard policy.accepts(url) else { return nil }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let final = http.url, policy.accepts(final), http.expectedContentLength <= Int64(limit) else { return nil }
            var data = Data(); for try await b in bytes { if data.count >= limit { return nil }; data.append(b) }; return (data,final)
        } catch { return nil }
    }
    var candidates: [URL] = []
    if let (htmlData, page) = await get(root, limit: 1_500_000), let html = String(data: htmlData, encoding: .utf8), let tagRE = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: .caseInsensitive), let attrRE = try? NSRegularExpression(pattern: "([a-zA-Z][a-zA-Z0-9_-]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))") {
        var links: [(Int,URL)] = []
        for match in tagRE.matches(in: html, range: NSRange(html.startIndex..., in: html)).prefix(200) {
            guard let range = Range(match.range,in:html) else { continue }; let tag = String(html[range]); var attrs: [String:String] = [:]
            for m in attrRE.matches(in: tag,range:NSRange(tag.startIndex...,in:tag)) { guard let k = Range(m.range(at:1),in:tag), let v = (2...4).compactMap({Range(m.range(at:$0),in:tag)}).first else {continue}; attrs[String(tag[k]).lowercased()] = String(tag[v]) }
            let rel = attrs["rel"]?.lowercased() ?? ""; guard let href = attrs["href"], let url = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: page)?.absoluteURL, policy.accepts(url) else { continue }
            if rel.contains("apple-touch-icon") { links.append((0,url)) } else if rel.split(separator:" ").contains("icon") { links.append((1,url)) }
        }
        candidates += links.sorted{$0.0<$1.0}.map{$0.1}
    }
    candidates += ["apple-touch-icon.png","apple-touch-icon-precomposed.png","favicon.ico"].map{root.appendingPathComponent($0)}
    var seen = Set<URL>(); var results: [IconCandidate] = []
    for url in candidates.filter({seen.insert($0).inserted}).prefix(multiple ? 10 : 5) {
        if Task.isCancelled { break }
        if let (data, final) = await get(url, limit: 8_000_000), let (png, size) = safePNG(data) {
            let item = IconCandidate(title: final.lastPathComponent.isEmpty ? host : final.lastPathComponent, png: png, pixels: size, source: final.absoluteString, page: nil)
            if !results.contains(where: { $0.png == png }) { results.append(item) }
            if !multiple && size >= 180 { break }
        }
    }
    return results.sorted { $0.pixels > $1.pixels }
}
func fetchIcon(_ host: String) async -> Pending? {
    guard let result = await fetchWebsiteIcons(host).first else { return nil }
    return Pending(png: result.png, source: result.source)
}

@MainActor struct MainView: View {
    @State private var store = Cache(safari: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari"))
    @State private var sites: [Site] = []; @State private var pending: [String: Pending] = [:]; @State private var replacements = Set<String>()
    @State private var marked = Set<String>()
    @StateObject private var updates = AppUpdates.shared
    @State private var showAbout = false
    @AppStorage("sif.workspace.grid") private var gridMode = true
    @AppStorage("sif.workspace.sidebar") private var showSidebar = true
    @AppStorage("sif.workspace.inspector") private var showInspector = true
    @AppStorage("sif.workspace.tileSize") private var iconSize = 62.0
    @State private var previewMode = false
    @State private var previewAfter = true

    @State private var anchor: String?
    @State private var confirmDiscard = false
    @State private var quickLook: Site?
    @State private var nativePreviewURL: URL?
    @State private var nativePreviewDirectory: URL?
    @State private var keyboardScrollTarget: String?
    @FocusState private var libraryFocused: Bool
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTechnical = false
    @State private var draftLoaded = false
    @State private var draftWritable = false
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var studioEditingHost: String?
    @State private var scanWorker: Task<(sites: [Site], folders: [FavoriteFolder]), Error>?
    @State private var scanCanCancel = false
    @State private var prepareTask: Task<Void, Never>?
    @State private var showBackups = false
    @State private var historySite: Site?
    @State private var historyEntries: [HistoricalIcon] = []
    @AppStorage("sif.workspace.previewDark") private var storedPreviewDark = true
    @AppStorage("sif.workspace.filter") private var storedFilter = 0
    @State private var undoPending: [String: Pending]?
    @State private var undoReplacements: Set<String> = []
    @State private var folders: [FavoriteFolder] = []; @State private var scope: FavoriteScope = .root
    @State private var selected: String?; @State private var filter = l10n("Wszystkie"); @State private var search = ""; @State private var message = l10n("Przeskanuj Ulubione Safari. Nic nie zostanie zmienione."); @State private var busy = false; @State private var confirm = false; @State private var confirmRestore = false; @State private var chosenBackup: URL?
    @State private var permissionDenied = false
    @State private var showPermission = false
    @State private var waitingForPermission = false
    @State private var permissionHelp = ""
    @State private var iconEditor: Site?
    @State private var customHosts = Set<String>()
    @State private var protectedIcons: [String: ProtectedIcon] = [:]
    @State private var recoveryHosts = Set<String>()
    @State private var resetHosts = Set<String>()
    @State private var resetScope: FavoriteScope = .root
    @State private var resetTrackedOnly = false
    @State private var confirmReset = false
    @State private var safariOpen = true
    private func refreshSafariStatus() { safariOpen = store.safariRunning }
    private func requireClosedSafari() -> Bool {
        let isOpen = store.safariRunning
        safariOpen = isOpen
        guard !isOpen else {
            message = l10n("Przejdź do Safari i naciśnij ⌘Q, aby zastosować zmiany.")
            return false
        }
        return true
    }
    private var scopedCustom: Set<String> { Set(scoped.filter { customHosts.contains($0.host) && $0.registered }.map { $0.host }) }
    func requestReset(_ hosts: Set<String>, in range: FavoriteScope, trackedOnly: Bool = false) {
        guard !hosts.isEmpty, !busy, !permissionDenied, requireClosedSafari() else { return }
        resetHosts = hosts; resetScope = range; resetTrackedOnly = trackedOnly; confirmReset = true
    }
    func executeReset() {
        guard !busy, requireClosedSafari() else { return }
        do {
            let saved = try store.reset(resetHosts, scope: resetScope, trackedOnly: resetTrackedOnly)
            for host in resetHosts { pending.removeValue(forKey: host); replacements.remove(host); marked.remove(host) }
            undoPending = nil
            let count = resetHosts.count
            runScan(presentPermission: true, completionMessage: l10n("Zresetowano {0} ikon. Otwórz Safari; w razie potrzeby odwiedź strony, aby pobrać oryginalne ikony. Kopia: {1}.", String(describing: count), String(describing: saved.lastPathComponent)))
        } catch { handleOperationError(error) }
    }
    private var filterChoices: [String] { [l10n("Wszystkie"), l10n("Brakujące"), l10n("Gotowe"), l10n("Własne")] }
    private func loadPreparedDraft() {
        guard !draftLoaded else { return }
        draftLoaded = true
        do {
            let saved = try store.readDraft()
            let byHost = Dictionary(uniqueKeysWithValues: sites.map { ($0.host, $0) })
            var recovered: [String: Pending] = [:]
            for (host, item) in saved {
                guard let current = byHost[host], current.registered, current.existing.map(iconDigest) == item.expectedDigest, safePNG(item.png) != nil else { continue }
                recovered[host] = item
            }
            pending = recovered; replacements = Set(recovered.keys.filter { byHost[$0]?.existing != nil })
            draftWritable = true
            if !saved.isEmpty { message = l10n("Odzyskano {0} przygotowanych ikon. Pominięto {1} nieaktualnych.", String(recovered.count), String(saved.count - recovered.count)) }
        } catch {
            draftWritable = false
            message = l10n("Nie można odczytać przygotowanych ikon.") + " " + error.localizedDescription
        }
    }
    @discardableResult private func persistPreparedDraft() -> Bool {
        draftSaveTask?.cancel(); draftSaveTask = nil
        DraftProtection.shared.pending = pending.count
        guard draftLoaded, draftWritable, !busy else { return pending.isEmpty && !busy }
        do { try store.saveDraft(pending); return true }
        catch { message = l10n("Nie można zapisać przygotowanych ikon.") + " " + error.localizedDescription; return false }
    }
    private func scheduleDraftSave() {
        DraftProtection.shared.pending = pending.count
        draftSaveTask?.cancel()
        guard draftLoaded, draftWritable, !busy else { return }
        draftSaveTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            persistPreparedDraft()
        }
    }
    private func recoverProtectedIcon(_ item: Site) {
        guard !busy, !permissionDenied, pending[item.host] == nil, recoveryHosts.contains(item.host),
              let saved = protectedIcons[item.host], let (normalized, _) = safePNG(saved.png) else { return }
        do {
            let display = try store.hasDisplayColumn() ? saved.display : nil
            let png = saved.png.starts(with: [137,80,78,71,13,10,26,10]) ? saved.png : normalized
            stage(item, result: Pending(png: png, source: l10n("Odzyskaj własną ikonę"), custom: true, display: display))
        } catch { handleOperationError(error) }
    }
    private func openHistory(_ item: Site) {
        guard !busy, !permissionDenied else { return }
        do { historyEntries = try store.history(for: item.host); historySite = item }
        catch { handleOperationError(error) }
    }
    var scoped: [Site] {
        var result: [Site] = []
        for original in sites {
            let links: [FavoriteLink] = original.locations.filter { scope.includes($0.folder) }
            if links.isEmpty { continue }
            var site = original
            let titles: [String] = links.map { $0.title }
            site.names = Set(titles).sorted()
            result.append(site)
        }
        result.sort { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return result
    }
    var shown: [Site] { scoped.filter { s in (filter == l10n("Wszystkie") || (filter == l10n("Brakujące") && (s.needsRepair || recoveryHosts.contains(s.host))) || (filter == l10n("Gotowe") && pending[s.host] != nil) || (filter == l10n("Własne") && customHosts.contains(s.host))) && (search.isEmpty || (s.title + s.host).localizedCaseInsensitiveContains(search)) } }
    var missing: [Site] { scoped.filter { $0.registered && ($0.needsRepair || recoveryHosts.contains($0.host)) && pending[$0.host] == nil } }
    var markedSites: [Site] { scoped.filter { marked.contains($0.host) && $0.registered } }
    var scopedPending: [String: Pending] { let hosts = Set(scoped.map(\.host)); return pending.filter { hosts.contains($0.key) } }
    var site: Site? { shown.first { $0.host == selected } }
    var scopeLabel: String { switch scope { case .all: return l10n("Wszystkie Ulubione"); case .root: return l10n("Bez folderu"); case .folder: return folders.first { $0.scope == scope }?.label ?? l10n("Folder") } }
    func openPrivacySettings() {
        waitingForPermission = true
        permissionHelp = l10n("Włącz dostęp dla Safari Icon Fixer, a następnie wróć tutaj. Jeśli dostęp nadal nie działa, zamknij aplikację (⌘Q) i uruchom ją ponownie.")
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"), NSWorkspace.shared.open(url) { return }
        if let url = URL(string: "x-apple.systempreferences:") { _ = NSWorkspace.shared.open(url) }
        permissionHelp = l10n("Otwórz Prywatność i ochrona → Pełny dostęp do dysku. Jeśli ustawienia nie otworzyły się automatycznie, uruchom je z menu Apple.")
    }
    func reportPermission(_ error: Error, present: Bool = true) {
        permissionDenied = true
        if present { showPermission = true }
        message = l10n("Brak dostępu do danych Safari: {0}", String(describing: error.localizedDescription))
        permissionHelp = l10n("Jeśli dostęp jest już włączony, zamknij aplikację (⌘Q) i uruchom ją ponownie.")
    }
    func handleOperationError(_ error: Error) {
        if isSafariPermissionError(error) { reportPermission(error) }
        else { message = error.localizedDescription }
    }
    func scan() { runScan(presentPermission: true) }
    func runScan(presentPermission: Bool, completionMessage: String? = nil) {
        guard !busy else { return }
        if draftLoaded { persistPreparedDraft() }
        studioEditingHost = nil; busy = true; DraftProtection.shared.busy = true
        scanCanCancel = completionMessage == nil
        message = l10n("Skanowanie Ulubionych…")
        let reader = store
        let worker = Task.detached(priority: .userInitiated) { try reader.scan() }
        scanWorker = worker
        Task { @MainActor in
            defer {
                scanWorker = nil; scanCanCancel = false; busy = false
                DraftProtection.shared.busy = false; persistPreparedDraft()
            }
            do {
            let result = try await worker.value
            guard !worker.isCancelled else { throw CancellationError() }
            sites = result.sites; folders = result.folders
            let protection = try store.captureKnownIcons(sites)
            let tracking = protection.registry
            protectedIcons = protection.icons
            recoveryHosts = Set(sites.filter { $0.registered && protection.needsRecovery(host: $0.host, current: $0.existing, displayCode: $0.displayCode) }.map(\.host))
            customHosts = Set(sites.compactMap { site -> String? in
                guard site.registered, let data = site.existing, tracking[site.host] == iconDigest(data) else { return nil }
                return site.host
            })
            if case .folder = scope, !folders.contains(where: { $0.scope == scope }) { scope = .root }
            let hosts = Set(sites.map(\.host)); pending = pending.filter { hosts.contains($0.key) }; replacements.formIntersection(hosts); marked.formIntersection(hosts); undoPending = nil
            permissionDenied = false; showPermission = false; waitingForPermission = false; permissionHelp = ""
            message = l10n("Odczytano {0} domen w Ulubionych. W wybranym zakresie: {1}.", String(describing: sites.count), String(describing: scoped.count))
            loadPreparedDraft()
            if let completionMessage { message = completionMessage }
        } catch is CancellationError {
            message = l10n("Skanowanie anulowane. Zachowano poprzedni widok.")
        } catch {
            sites = []; folders = []; selected = nil; customHosts = []; protectedIcons = [:]; recoveryHosts = []
            if isSafariPermissionError(error) {
                reportPermission(error, present: presentPermission)
            } else {
                permissionDenied = false; showPermission = false; waitingForPermission = false
                marked = []; scope = .root
                message = l10n("Nie można odczytać Safari: {0}", String(describing: error.localizedDescription))
            }
        }
        }
    }
    func prepareDisplay(_ targets: [Site], style: SafariIconDisplay) {
        guard !busy, !permissionDenied else { return }
        do {
            guard try store.hasDisplayColumn() else { throw fail(l10n("Brak parametru stylu w tej wersji Safari. Nic nie zmieniono.")) }
            rememberDraft()
            var count = 0
            for site in targets where site.registered {
                guard let data = pending[site.host]?.png ?? site.existing else { continue }
                let previous = pending[site.host]
                let expected = previous?.expectedDigest ?? site.existing.map(iconDigest)
                pending[site.host] = Pending(png: data, source: (previous.map { $0.source + " · " } ?? l10n("Zachowano obraz · ")) + style.label, custom: true, display: style, expectedDigest: expected)
                replacements.insert(site.host)
                count += 1
            }
            message = l10n("Przygotowano styl dla {0} ikon (bez pobierania). Zamknij Safari i kliknij Zastosuj.", String(describing: count))
        } catch { handleOperationError(error) }
    }
    func prepare() { prepareSites(missing) }
    func prepareMarked() { prepareSites(markedSites) }
    func prepareSites(_ targets: [Site]) {
        guard !busy, !permissionDenied, !targets.isEmpty else { return }
        rememberDraft()
        busy = true; DraftProtection.shared.busy = true
        prepareTask = Task {
            defer { prepareTask = nil; busy = false; DraftProtection.shared.busy = false; persistPreparedDraft() }
            var failures = 0
            let supportsDisplay = (try? store.hasDisplayColumn()) == true
            for (i, site) in targets.enumerated() {
                if Task.isCancelled { break }
                message = l10n("Przygotowanie {0}/{1}: {2}", String(describing: i+1), String(describing: targets.count), String(describing: site.host))
                guard site.registered else { failures += 1; continue }
                if pending[site.host] != nil { continue }
                if recoveryHosts.contains(site.host), let saved = protectedIcons[site.host], let (normalized, _) = safePNG(saved.png) {
                    let png = saved.png.starts(with: [137,80,78,71,13,10,26,10]) ? saved.png : normalized
                    pending[site.host] = Pending(png: png, source: l10n("Odzyskaj własną ikonę"), custom: true, display: supportsDisplay ? saved.display : nil, expectedDigest: site.existing.map(iconDigest))
                    if site.existing != nil { replacements.insert(site.host) }
                    continue
                }
                if let existing = site.existing, let (png, _) = safePNG(existing) {
                    let isPNG = existing.starts(with: [UInt8]( [137, 80, 78, 71, 13, 10, 26, 10] ))
                    let data = isPNG ? existing : png
                    pending[site.host] = Pending(png: data, source: l10n("Zachowano obecną grafikę i styl Safari"), custom: customHosts.contains(site.host), expectedDigest: iconDigest(existing))
                    replacements.insert(site.host)
                } else if let p = await fetchIcon(site.host) {
                    if Task.isCancelled { break }
                    pending[site.host] = p
                    if site.existing != nil { replacements.insert(site.host) }
                } else { failures += 1 }
            }
            if Task.isCancelled { message = l10n("Przerwano pobieranie. Zachowano przygotowane ikony."); return }
            message = l10n("Przygotowano {0} ikon w zakresie. Nie zmieniono Safari. Niepowodzenia: {1}.", String(describing: scopedPending.count), String(describing: failures))
        }
    }
    private var libraryCommandsAvailable: Bool {
        !busy && !permissionDenied && !previewMode && !showAbout && !showPermission && !showBackups && iconEditor == nil && historySite == nil && quickLook == nil && nativePreviewURL == nil && !confirm && !confirmDiscard && !confirmReset && !confirmRestore
    }
    private func openNativePreview(_ item: Site) {
        guard nativePreviewURL == nil else { return }
        guard let data = pending[item.host]?.png ?? item.existing, let (png, _) = safePNG(data) else { quickLook = item; return }
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("SIF-QuickLook-" + UUID().uuidString, isDirectory: true)
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let url = directory.appendingPathComponent("Icon.png")
            try png.write(to: url, options: .atomic)
            nativePreviewDirectory = directory
            nativePreviewURL = url
        } catch { try? fm.removeItem(at: directory); quickLook = item }
    }
    private func moveLibrarySelection(_ direction: MoveCommandDirection, columns: Int) {
        guard libraryFocused, libraryCommandsAvailable else { return }
        let order = shown.map(\.host)
        let offset: Int
        switch direction { case .left: offset = -1; case .right: offset = 1; case .up: offset = -columns; case .down: offset = columns; @unknown default: return }
        guard let target = LibrarySelection.keyboardTarget(ordered: order, current: selected, offset: offset) else { return }
        let extend = NSEvent.modifierFlags.contains(.shift)
        let next = LibrarySelection.click(target, ordered: order, selected: marked, anchor: anchor, extend: extend, toggle: false)
        studioEditingHost = nil; marked = next.selected; anchor = next.anchor; selected = target; keyboardScrollTarget = target
    }
    private func selectSite(_ item: Site) {
        libraryFocused = true
        let flags = NSEvent.modifierFlags
        let selection = LibrarySelection.click(item.host, ordered: shown.map(\.host), selected: marked, anchor: anchor, extend: flags.contains(.shift), toggle: flags.contains(.command))
        marked = selection.selected
        anchor = selection.anchor
        selected = marked.contains(item.host) ? item.host : shown.first(where: { marked.contains($0.host) })?.host
    }
    private func selectAllVisible() {
        marked = Set(shown.map(\.host)); selected = shown.first?.host; anchor = selected
    }
    private func clearSelection() { marked = []; selected = nil; anchor = nil }
    private func rememberDraft() { studioEditingHost = nil; undoPending = pending; undoReplacements = replacements }
    private func undoDraft() {
        guard !busy, let previous = undoPending else { return }
        studioEditingHost = nil; pending = previous; replacements = undoReplacements; undoPending = nil
    }
    @discardableResult private func stage(_ item: Site, result: Pending, live: Bool = false) -> Bool {
        guard !busy, !permissionDenied, let current = scoped.first(where: { $0.host == item.host && $0.registered }), current.existing.map(iconDigest) == item.existing.map(iconDigest) else { return false }
        let prior = pending[item.host]
        let next = Pending(png: result.png, source: result.source, custom: result.custom, display: result.display, expectedDigest: prior?.expectedDigest ?? item.existing.map(iconDigest))
        if prior == next { return true }
        if !live || studioEditingHost != item.host { rememberDraft() }
        studioEditingHost = live ? item.host : nil
        pending[item.host] = next
        if item.existing != nil { replacements.insert(item.host) }
        scheduleDraftSave()
        message = l10n("Przygotowano ikonę: {0}. Kliknij Zastosuj, aby zapisać.", item.host)
        return true
    }
    private func preparePreset(_ preset: StudioPreset, targets: [Site]) {
        guard !busy, !permissionDenied else { return }
        do {
            guard try store.hasDisplayColumn() else { throw fail(l10n("Brak parametru stylu w tej wersji Safari. Nic nie zmieniono.")) }
            rememberDraft()
            var count = 0
            for item in targets where item.registered {
                guard let data = pending[item.host]?.png ?? item.existing, let art = IconArtwork(data), art.separate,
                      let result = composeArtwork(art, background: preset.background, color: preset.color, inset: 0.12, lightening: 0.40) else { continue }
                let expected = pending[item.host]?.expectedDigest ?? item.existing.map(iconDigest)
                pending[item.host] = Pending(png: result, source: preset.label, custom: true, display: .fullTile, expectedDigest: expected)
                if item.existing != nil { replacements.insert(item.host) }
                count += 1
            }
            message = l10n("Przygotowano {0} ikon. Pominięto {1}: brak grafiki lub złożone tło.", String(count), String(targets.count-count))
        } catch { handleOperationError(error) }
    }
    private func acceptDrop(_ providers: [NSItemProvider], onto item: Site) -> Bool {
        guard !busy, !permissionDenied, item.registered, let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, _ in
                let url = (value as? URL) ?? (value as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                guard let url, url.isFileURL else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true, let size = values.fileSize, size <= 8_000_000,
                      let data = try? Data(contentsOf: url), let (png, _) = safePNG(data) else { return }
                Task { @MainActor in stage(item, result: Pending(png: png, source: url.lastPathComponent, custom: true, display: hasTransparentPixels(png) ? .systemTile : .fullTile)) }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data, let (png, _) = safePNG(data) else { return }
                Task { @MainActor in stage(item, result: Pending(png: png, source: l10n("Importuj grafikę"), custom: true, display: hasTransparentPixels(png) ? .systemTile : .fullTile)) }
            }
            return true
        }
        return false
    }
    func toggleMarked(_ host: String, _ value: Bool) {
        if value { marked.insert(host) } else { marked.remove(host) }
    }
    private func visualStatus(_ item: Site) -> String {
        if pending[item.host] != nil { return l10n("Gotowa do zapisania") }
        if recoveryHosts.contains(item.host) { return l10n("Własna ikona została zmieniona") }
        if item.needsRepair { return item.status }
        return customHosts.contains(item.host) ? l10n("Własna ikona") : item.status
    }
    func siteRow(_ site: Site) -> some View {
        Button { selectSite(site) } label: {
            HStack(spacing: 10) {
                safariTile(site, size: 36, after: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(site.title).lineLimit(1)
                    Text(site.host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(pending[site.host] != nil ? l10n("Gotowa") : (recoveryHosts.contains(site.host) ? l10n("Własna ikona została zmieniona") : (customHosts.contains(site.host) ? l10n("Własna") : site.status)))
                    .font(.caption).foregroundStyle(pending[site.host] != nil ? Color.green : Color.secondary)
            }.padding(9).contentShape(Rectangle())
        }.buttonStyle(.plain)
        .modifier(IconInteractionFeedback(selected: marked.contains(site.host), accent: purple, radius: 8, onDrop: { acceptDrop($0, onto: site) }))
        .accessibilityLabel(site.title).accessibilityValue(visualStatus(site)).accessibilityAddTraits(marked.contains(site.host) ? .isSelected : [])
        .contextMenu { siteMenu(site) }
    }
    func cacheDetails(_ site: Site) -> String {
        let flags = site.downloadFlags.map { String($0) } ?? l10n("brak")
        let size = site.pixelSize.map { "\($0) px" } ?? l10n("brak")
        let display = site.displayCode.map { code in SafariIconDisplay(rawValue: code)?.label ?? l10n("Kod {0}", String(describing: code)) } ?? l10n("Nieznany")
        return l10n("Cache: {0} · aktywna: {1} · status: {2} · styl: {3}", String(describing: size), String(describing: site.active ? l10n("tak") : l10n("nie")), String(describing: flags), String(describing: display))
    }
    func choose(_ s: Site) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8_000_000,
                  let (png, _) = safePNG(try Data(contentsOf: url)) else { throw fail(l10n("Nieobsługiwany lub uszkodzony obraz (limit 8 MB).")) }
            stage(s, result: Pending(png: png, source: url.lastPathComponent, custom: true, display: hasTransparentPixels(png) ? .systemTile : .fullTile))
        } catch { message = error.localizedDescription }
    }
    func write() {
        guard !busy else { return }
        guard !permissionDenied else { showPermission = true; return }
        guard requireClosedSafari() else { return }
        let batch = scopedPending
        do {
            let (backup,count) = try store.apply(batch,allowingReplacement:replacements,scope:scope)
            for host in batch.keys { pending.removeValue(forKey:host); replacements.remove(host); marked.remove(host) }
            undoPending = nil
            runScan(presentPermission: true, completionMessage: l10n("Zapisano {0} ikon. Kopia: {1}. Otwórz Safari i sprawdź efekt.", String(describing: count), String(describing: backup.lastPathComponent)))
        } catch { handleOperationError(error) }
    }
    func selectBackup() { guard !busy else { return }; chosenBackup = nil; showBackups = true }
    func tile(_ data: Data?, fallback: String, size: CGFloat) -> some View { Group { if let data, let image = NSImage(data:data) { Image(nsImage:image).resizable().scaledToFit() } else { ZStack { RoundedRectangle(cornerRadius:size*0.22).fill(.gray.opacity(0.2)); Text(fallback.prefix(1).uppercased()).font(.system(size:size*0.45,weight:.medium)).foregroundStyle(.secondary) } } }.frame(width:size,height:size) }
    private var purple: Color { Color(red: 137.0/255, green: 96.0/255, blue: 232.0/255) }
    private var surface: Color { Color(nsColor: .controlBackgroundColor) }
    private func scopeButton(_ label: String, symbol: String, value: FavoriteScope, depth: Int = 0, status: String? = nil, count: Int? = nil) -> some View {
        let active = scope == value && filter == (status ?? l10n("Wszystkie"))
        return Button { clearSelection(); scope = value; filter = status ?? l10n("Wszystkie"); previewMode = false } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(active ? purple : Color.secondary).frame(width: 17)
                Text(label).font(.callout).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if let count { Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }.padding(.vertical, 7).padding(.horizontal, 9).padding(.leading, CGFloat(min(depth, 3)) * 9)
                .background(active ? purple.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(label).disabled(busy || permissionDenied)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().scaledToFit().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Icon Fixer").font(.headline)
                    Text("Safari • \(AppReleaseInfo.version)").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 4)
            Text(l10n("BIBLIOTEKA")).font(.caption2.weight(.semibold)).tracking(1.1).foregroundStyle(.secondary)
            scopeButton(l10n("Wszystkie Ulubione"), symbol: "square.grid.2x2", value: .all, count: sites.count)
            scopeButton(l10n("Do sprawdzenia"), symbol: "exclamationmark.circle", value: .all, status: l10n("Brakujące"), count: sites.filter { $0.needsRepair || recoveryHosts.contains($0.host) }.count)
            scopeButton(l10n("Własne"), symbol: "sparkle", value: .all, status: l10n("Własne"), count: customHosts.count)
            scopeButton(l10n("Gotowe"), symbol: "checkmark.circle", value: .all, status: l10n("Gotowe"), count: pending.count)
            scopeButton(l10n("Bez folderu"), symbol: "star", value: .root)
            Text(l10n("FOLDERY")).font(.caption2.weight(.semibold)).tracking(1.1).foregroundStyle(.secondary).padding(.top, 5)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(folders) { folder in
                        scopeButton(folder.titles.last ?? folder.label, symbol: "folder", value: folder.scope, depth: max(0, folder.path.count - 1))
                    }
                }
            }
            Divider()
            Button { selectBackup() } label: { Label(l10n("Kopie zapasowe"), systemImage: "clock.arrow.circlepath") }.buttonStyle(.plain).disabled(busy || permissionDenied)
            Button { if permissionDenied { showPermission = true } else { openPrivacySettings() } } label: { Label(l10n("Uprawnienia"), systemImage: "gearshape") }.buttonStyle(.plain)
            Button {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil) }
            } label: { Label(l10n("Otwórz Safari"), systemImage: "safari") }.buttonStyle(.plain)
            Button { showAbout = true } label: { Label(l10n("O aplikacji"), systemImage: "info.circle") }.buttonStyle(.plain)

        }.padding(12).frame(minWidth: 170, idealWidth: 205, maxWidth: 270, maxHeight: .infinity, alignment: .topLeading)
            .background(.regularMaterial)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 9) {
                Button { showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }.help(l10n("Pasek boczny")).accessibilityLabel(l10n("Pasek boczny"))
                Spacer(minLength: 0)
                Button(action: scan) { Image(systemName: "arrow.clockwise") }.help(l10n("Przeskanuj Ulubione")).accessibilityLabel(l10n("Przeskanuj Ulubione")).disabled(busy)
                Button { showInspector.toggle() } label: { Image(systemName: "sidebar.right") }.help(l10n("Panel edycji")).accessibilityLabel(l10n("Panel edycji"))
            }.buttonStyle(.borderless)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(scope == .all && filter != l10n("Wszystkie") ? (filter == l10n("Brakujące") ? l10n("Do sprawdzenia") : filter) : scopeLabel).font(.system(size: 28, weight: .semibold)).lineLimit(1)
                    Text(l10n("{0} stron · {1} do sprawdzenia", String(scoped.count), String(scoped.filter { $0.needsRepair || recoveryHosts.contains($0.host) }.count)))
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 5)
                Button(action: prepare) { Label(l10n("Szybka naprawa"), systemImage: "wand.and.stars") }
                    .buttonStyle(.borderedProminent).help(l10n("Przygotuj brakujące, nieaktywne lub zmienione własne ikony. Zatwierdź przed zapisem."))
                    .disabled(busy || permissionDenied || missing.isEmpty)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private var resetMenu: some View {
        Menu {
            Button(l10n("Domyślne — zaznaczone ({0})", String(describing: markedSites.count))) { requestReset(Set(markedSites.map { $0.host }), in: scope) }.disabled(markedSites.isEmpty)
            Button(l10n("Domyślne — własne w zakresie ({0})", String(describing: scopedCustom.count))) { requestReset(scopedCustom, in: scope, trackedOnly: true) }.disabled(scopedCustom.isEmpty)
            Button(l10n("Domyślne — wszystkie własne ({0})", String(describing: customHosts.count))) { requestReset(customHosts, in: .all, trackedOnly: true) }.disabled(customHosts.isEmpty)
        } label: { Label(l10n("Przywróć domyślne"), systemImage: "arrow.uturn.backward") }.disabled(busy || permissionDenied)
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Picker(l10n("Widok"), selection: $previewMode) {
                    Text(l10n("Ikony")).tag(false); Text(l10n("Podgląd Safari")).tag(true)
                }.labelsHidden().pickerStyle(.segmented).frame(maxWidth: 270)
                Spacer(minLength: 0)
                if !previewMode {
                    Picker(l10n("Widok"), selection: $gridMode) {
                        Image(systemName: "square.grid.2x2").tag(true); Image(systemName: "list.bullet").tag(false)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 70)
                    Menu { Button("48") { iconSize = 48 }; Button("62") { iconSize = 62 }; Button("80") { iconSize = 80 } } label: { Image(systemName: "textformat.size") }.help(l10n("Rozmiar ikon"))
                }
            }
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(l10n("Szukaj strony…"), text: $search).textFieldStyle(.plain).focused($searchFocused).accessibilityLabel(l10n("Szukaj strony…"))
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(l10n("Wyczyść wyszukiwanie")) }
                }.padding(8).background(surface, in: RoundedRectangle(cornerRadius: 8))
                Picker(l10n("Status"), selection: $filter) { ForEach([l10n("Wszystkie"), l10n("Brakujące"), l10n("Gotowe"), l10n("Własne")], id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(maxWidth: 145)
            }
            if !previewMode { selectionBar }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private var selectionBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button(l10n("Zaznacz widoczne"), action: selectAllVisible)
                Button(l10n("Odznacz w zakresie"), action: clearSelection)
            } label: { Label(l10n("Zaznaczenie ({0})", String(markedSites.count)), systemImage: "checkmark.square") }
            Spacer(minLength: 0)
            if !markedSites.isEmpty {
                Button(action: prepareMarked) { Image(systemName: "arrow.clockwise") }.help(l10n("Napraw wyświetlanie")).accessibilityLabel(l10n("Napraw wyświetlanie"))
                Menu {
                    ForEach(StudioPreset.allCases, id: \.self) { preset in Button(preset.label) { preparePreset(preset, targets: markedSites) } }
                    Divider()
                    Button(l10n("Pełny kafelek — bez szarej ramki")) { prepareDisplay(markedSites, style: .fullTile) }
                    Button(l10n("Tło systemowe")) { prepareDisplay(markedSites, style: .systemTile) }
                } label: { Label("Color Studio", systemImage: "paintpalette") }
                resetMenu
            } else {
                Text(l10n("⌘ lub ⇧, aby zaznaczyć więcej ikon")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }.controlSize(.small).disabled(busy)
    }
    private func safariTile(_ item: Site, size: CGFloat, after: Bool) -> some View {
        let data = after ? (pending[item.host]?.png ?? item.existing) : item.existing
        let style = after ? (pending[item.host]?.display?.rawValue ?? item.displayCode) : item.displayCode
        let full = style == SafariIconDisplay.fullTile.rawValue
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(Color(white: 0.50))
            if let data, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().frame(width: full ? size : size * 0.83, height: full ? size : size * 0.83) }
            else { Text(item.title.prefix(1).uppercased()).font(.system(size: size * 0.43, weight: .medium)).foregroundStyle(.white) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
    @ViewBuilder private func siteMenu(_ item: Site) -> some View {
        Button(l10n("Personalizuj ikonę")) { iconEditor = item }.disabled(!item.registered || busy)
        Button(l10n("Napraw wyświetlanie")) { prepareSites([item]) }.disabled(!item.registered || busy)
        Button(l10n("Importuj grafikę")) { choose(item) }.disabled(!item.registered || busy)
        Button(l10n("Szybki podgląd")) { openNativePreview(item) }
        Button(l10n("Porównaj przed i po")) { quickLook = item }
        Button(l10n("Historia ikony")) { openHistory(item) }
        if recoveryHosts.contains(item.host) {
            Button(l10n("Odzyskaj własną ikonę")) { recoverProtectedIcon(item) }.disabled(busy || pending[item.host] != nil)
        }
        Divider()
        Button(l10n("Przywróć domyślną ikonę Safari"), role: .destructive) { requestReset([item.host], in: scope) }.disabled(!item.registered || busy)
    }
    private func iconCard(_ item: Site) -> some View {
        let isSelected = marked.contains(item.host)
        return Button { selectSite(item) } label: {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    safariTile(item, size: CGFloat(iconSize), after: true).shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                    if pending[item.host] != nil || item.needsRepair || recoveryHosts.contains(item.host) || customHosts.contains(item.host) {
                        Image(systemName: pending[item.host] != nil ? "checkmark.circle.fill" : ((item.needsRepair || recoveryHosts.contains(item.host)) ? "exclamationmark.circle.fill" : "sparkle"))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(pending[item.host] != nil ? Color.green : ((item.needsRepair || recoveryHosts.contains(item.host)) ? .orange : purple))
                            .padding(3).background(surface, in: Circle()).offset(x: 5, y: -5)
                    }
                }
                Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
            }.padding(.vertical, 10).padding(.horizontal, 4).frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .modifier(IconInteractionFeedback(selected: isSelected, accent: purple, radius: 12, onDrop: { acceptDrop($0, onto: item) }))
        .help(item.title + " · " + visualStatus(item)).accessibilityLabel(item.title).accessibilityValue(visualStatus(item))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu { siteMenu(item) }
    }
    private var safariPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker(l10n("Podgląd"), selection: $previewAfter) { Text(l10n("Przed")).tag(false); Text(l10n("Po zmianie")).tag(true) }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 230)
                Spacer()
                Button { storedPreviewDark.toggle() } label: { Image(systemName: storedPreviewDark ? "sun.max" : "moon") }.help(l10n("Zmień motyw podglądu"))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 5) {
                        ForEach([Color.red, Color.yellow, Color.green], id: \.self) { tint in Circle().fill(tint).frame(width: 9, height: 9) }
                        Spacer(); RoundedRectangle(cornerRadius: 5).fill(.gray.opacity(0.25)).frame(width: 115, height: 15); Spacer()
                    }
                    Text(l10n("Ulubione")).font(.title2.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 13)], spacing: 18) {
                        ForEach(shown) { item in
                            VStack(spacing: 7) { safariTile(item, size: 58, after: previewAfter); Text(item.title).font(.caption).lineLimit(2).multilineTextAlignment(.center) }
                        }
                    }
                }.padding(20).foregroundStyle(storedPreviewDark ? Color.white : Color.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.background(storedPreviewDark ? Color(red: 0.16, green: 0.16, blue: 0.18) : Color(white: 0.94), in: RoundedRectangle(cornerRadius: 13))
            Text(l10n("Symulacja wyglądu, nie zrzut Safari. Kolejność może się różnić.")).font(.caption).foregroundStyle(.secondary)
        }.padding(3)
    }
    @ViewBuilder private func libraryKeyboard<Content: View>(_ content: Content, columns: Int) -> some View {
        let focused = content.focusable().focused($libraryFocused)
            .onMoveCommand { direction in moveLibrarySelection(direction, columns: columns) }
        if #available(macOS 14.0, *) {
            focused.onKeyPress(.space) {
                guard libraryFocused, libraryCommandsAvailable, let item = site else { return .ignored }
                openNativePreview(item); return .handled
            }
        } else { focused }
    }
    private var keyboardLibrary: some View {
        GeometryReader { geometry in
            let minimum = max(90.0, iconSize + 24)
            let columns = gridMode ? LibrarySelection.gridColumns(width: Double(geometry.size.width) - 8, minimum: minimum, spacing: 9) : 1
            ScrollViewReader { proxy in
                libraryKeyboard(ScrollView {
                    if gridMode {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: CGFloat(minimum)), spacing: 9)], spacing: 10) {
                            ForEach(shown) { iconCard($0).id($0.host) }
                        }.padding(4)
                    } else {
                        LazyVStack(spacing: 2) { ForEach(shown) { siteRow($0).id($0.host) } }.padding(2)
                    }
                }, columns: columns)
                .onChange(of: keyboardScrollTarget) { target in
                    guard let target else { return }
                    if reduceMotion { proxy.scrollTo(target) }
                    else { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(target) } }
                    keyboardScrollTarget = nil
                }
            }
        }
    }
    private var library: some View {
        VStack(spacing: 0) {
            if shown.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 36, weight: .light)).foregroundStyle(purple)
                    Text(l10n("Brak ikon w tym widoku")).font(.headline)
                    Text(l10n("Zmień filtr lub zakres Ulubionych.")).font(.caption).foregroundStyle(.secondary)
                    Button(l10n("Wszystkie")) { scope = .all; filter = l10n("Wszystkie"); search = "" }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if previewMode { safariPreview }
            else { keyboardLibrary }
        }.frame(minWidth: 330, maxWidth: .infinity, maxHeight: .infinity)
    }
    private func iconActions(_ item: Site) -> some View {
        Menu {
            Button(l10n("Szybki podgląd")) { openNativePreview(item) }
            Button(l10n("Porównaj przed i po")) { quickLook = item }
            Button(l10n("Importuj grafikę")) { choose(item) }.disabled(busy || !item.registered)
            Button(l10n("Napraw wyświetlanie")) { prepareSites([item]) }.disabled(busy || !item.registered || pending[item.host] != nil)
            Button(l10n("Historia ikony")) { openHistory(item) }.disabled(busy)
            if recoveryHosts.contains(item.host) {
                Button(l10n("Odzyskaj własną ikonę")) { recoverProtectedIcon(item) }.disabled(busy || pending[item.host] != nil)
            }
            Button(l10n("Informacje")) { showTechnical.toggle() }
            if pending[item.host] != nil {
                Divider()
                Button(l10n("Odrzuć zmianę")) { rememberDraft(); pending.removeValue(forKey: item.host); replacements.remove(item.host) }.disabled(busy)
            }
            Divider()
            Button(l10n("Przywróć domyślną ikonę Safari"), role: .destructive) { requestReset([item.host], in: scope) }.disabled(busy || !item.registered)
        } label: { Image(systemName: "ellipsis.circle").font(.system(size: 17)) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .fixedSize().help(l10n("Więcej działań")).accessibilityLabel(l10n("Więcej działań"))
    }
    @ViewBuilder private func detail(_ item: Site) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.headline).lineLimit(2)
                    Text(item.host).font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                }
                Spacer(minLength: 0)
                iconActions(item)
            }
            if recoveryHosts.contains(item.host) && pending[item.host] == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Label(l10n("Własna ikona została zmieniona"), systemImage: "exclamationmark.circle").font(.callout.weight(.medium))
                    Text(l10n("Twoja grafika jest zachowana lokalnie. Odzyskaj ją i zatwierdź zmianę.")).font(.caption).foregroundStyle(.secondary)
                    Button(l10n("Odzyskaj własną ikonę")) { recoverProtectedIcon(item) }.buttonStyle(.bordered).disabled(busy || permissionDenied)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            }
            if let data = pending[item.host]?.png ?? item.existing {
                let currentStyle = pending[item.host]?.display ?? item.displayCode.flatMap(SafariIconDisplay.init(rawValue:))
                InlineIconStudio(data: data, initialDisplay: currentStyle, staged: pending[item.host] != nil,
                                 changeImage: { iconEditor = item }) { png, display in
                    stage(item, result: Pending(png: png, source: "Color Studio", custom: true, display: display), live: true)
                }.id(item.host)
                    .disabled(!item.registered || busy || permissionDenied)
            } else {
                VStack(spacing: 12) {
                    safariTile(item, size: 100, after: true)
                    Text(item.status).font(.caption).foregroundStyle(.secondary)
                    Button { prepareSites([item]) } label: { Label(l10n("Pobierz brakujące ikony"), systemImage: "arrow.down.circle") }
                        .buttonStyle(.borderedProminent).disabled(busy || !item.registered || permissionDenied)
                    Button { iconEditor = item } label: { Label(l10n("Zmień grafikę"), systemImage: "photo") }
                        .buttonStyle(.bordered).disabled(busy || !item.registered || permissionDenied)
                }.frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            if item.locations.contains(where: { !scope.includes($0.folder) }) {
                Label(l10n("Wspólna ikona także poza tym zakresem."), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !item.registered { Text(l10n("Otwórz stronę w Safari i przeskanuj ponownie.")).font(.caption).foregroundStyle(.secondary) }
            if showTechnical {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(l10n("Informacje")).font(.caption.weight(.semibold))
                    Text(cacheDetails(item)).font(.caption).foregroundStyle(.secondary)
                    Text(Array(Set(item.locations.map { $0.folderTitles.isEmpty ? l10n("Bez folderu") : $0.folderTitles.joined(separator: " / ") })).sorted().joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    if let p = pending[item.host] { Text(p.source).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
    private var inspector: some View {
        ScrollView {
            if let s = site { detail(s) }
            else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text(l10n("Wybierz ikonę")).font(.headline)
                    Text(l10n("Zmieniaj obraz, tło i margines w edytorze.")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.top, 40)
            }
        }.padding(16).frame(minWidth: 255, idealWidth: 305, maxWidth: 400, maxHeight: .infinity).background(.regularMaterial)
    }
    private var safariStatus: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: safariOpen ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(safariOpen ? Color.orange : Color.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(safariOpen ? l10n("Safari jest otwarte") : l10n("Safari jest zamknięte"))
                    .font(.callout.weight(.medium))
                if safariOpen {
                    Text(l10n("Przejdź do Safari i naciśnij ⌘Q, aby zastosować zmiany."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }.padding(9)
            .background((safariOpen ? Color.orange : Color.green).opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityElement(children: .combine)
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                if busy { ProgressView().controlSize(.small) } else { Image(systemName: "info.circle").foregroundStyle(.secondary) }
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(message).textSelection(.enabled)
                Spacer(minLength: 0)
                if (scanWorker != nil && scanCanCancel) || prepareTask != nil {
                    Button(l10n("Anuluj")) { scanWorker?.cancel(); prepareTask?.cancel() }.controlSize(.small)
                }
            }
            safariStatus
            if !pending.isEmpty || undoPending != nil {
                HStack(spacing: 8) {
                    Button { clearSelection(); scope = .all; filter = l10n("Gotowe"); search = ""; previewMode = false } label: { Text(l10n("{0} zmian", String(pending.count))).font(.callout.weight(.medium)).foregroundStyle(purple) }.buttonStyle(.plain).disabled(pending.isEmpty || busy)
                    Spacer(minLength: 0)
                    Button { undoDraft() } label: { Image(systemName: "arrow.uturn.backward") }.help(l10n("Cofnij przygotowaną zmianę")).disabled(undoPending == nil || busy)
                    Button(l10n("Odrzuć zmianę")) { confirmDiscard = true }.disabled(scopedPending.isEmpty || busy)
                    Button(l10n("Zastosuj ({0})", String(scopedPending.count))) { if requireClosedSafari() { confirm = true } }.buttonStyle(.borderedProminent).disabled(busy || permissionDenied || scopedPending.isEmpty || safariOpen)
                }.padding(9).background(purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private var permissionSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n("Wymagany dostęp do dysku")).font(.title2.bold())
                    Text(l10n("Safari Icon Fixer nie może odczytać lub zmienić pamięci ikon Safari."))
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            Text(l10n("1. Otwórz Ustawienia systemowe → Prywatność i ochrona → Pełny dostęp do dysku."))
            Text(l10n("2. Włącz Safari Icon Fixer na liście. Jeśli go nie ma, kliknij + i wybierz aplikację z folderu Aplikacje."))
            Text(l10n("3. Wróć tutaj i sprawdź dostęp ponownie. Jeśli macOS poprosi o ponowne uruchomienie aplikacji, zaakceptuj."))
            Text(l10n("To szerokie uprawnienie systemowe. Aplikacja używa go do lokalnego dostępu do zakładek i cache ikon Safari; możesz je później cofnąć."))
                .font(.caption).foregroundStyle(.secondary)
            if !permissionHelp.isEmpty {
                Text(permissionHelp).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button(l10n("Później")) { waitingForPermission = false; showPermission = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(l10n("Sprawdź ponownie"), action: scan)
                Button(l10n("Otwórz ustawienia"), action: openPrivacySettings)
                    .buttonStyle(.borderedProminent)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
        .frame(width: 520)
    }
    var body: some View {
        HSplitView {
            if showSidebar { sidebar }
            VStack(alignment: .leading, spacing: 13) {
                header
                controls.disabled(permissionDenied)
                library.layoutPriority(1).disabled(permissionDenied || busy)
                Divider()
                footer
            }.padding(18).frame(minWidth: 365, idealWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
            if showInspector { inspector.disabled(permissionDenied) }
        }
        .frame(minWidth: 850, minHeight: 500)
        .tint(purple)
        .onAppear {
            DraftProtection.shared.flushDraft = { persistPreparedDraft() }
            refreshSafariStatus(); filter = filterChoices.indices.contains(storedFilter) ? filterChoices[storedFilter] : filterChoices[0]; scan()
        }
        .onDisappear { if !busy { persistPreparedDraft() } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in refreshSafariStatus() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in refreshSafariStatus() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in refreshSafariStatus() }
        .task { updates.checkAtLaunch() }
        .sheet(isPresented: $showAbout) { AppAboutView(updates: updates) }
        .onReceive(NotificationCenter.default.publisher(for: .sifAbout)) { _ in showAbout = true }
        .onReceive(NotificationCenter.default.publisher(for: .sifUpdate)) { _ in
            updates.check()
        }
        .sheet(item: $iconEditor) { site in
            IconSearchView(host: site.host, title: site.names.first ?? site.host, existing: pending[site.host]?.png ?? site.existing) { result in
                stage(site, result: result)
            }
        }
        .sheet(isPresented: $showPermission, onDismiss: { waitingForPermission = false }) { permissionSheet }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSafariStatus()
            if waitingForPermission && permissionDenied { runScan(presentPermission: false) }
            else if waitingForPermission { waitingForPermission = false }
        }
        .onChange(of: scope) { _ in clearSelection() }
        .onChange(of: filter) { value in clearSelection(); storedFilter = filterChoices.firstIndex(of: value) ?? 0 }
        .onChange(of: search) { _ in clearSelection() }
        .onChange(of: selected) { _ in studioEditingHost = nil }
        .onChange(of: pending) { _ in scheduleDraftSave() }
        .onChange(of: busy) { value in DraftProtection.shared.busy = value; if !value { persistPreparedDraft() } }
        .onReceive(NotificationCenter.default.publisher(for: .sifUndoDraft)) { _ in undoDraft() }
        .onReceive(NotificationCenter.default.publisher(for: .sifSelectAll)) { _ in if !busy && !permissionDenied { selectAllVisible() } }
        .onReceive(NotificationCenter.default.publisher(for: .sifQuickLook)) { _ in if libraryCommandsAvailable, let item = site { openNativePreview(item) } }
        .onReceive(NotificationCenter.default.publisher(for: .sifCompare)) { _ in if libraryCommandsAvailable, let item = site { quickLook = item } }
        .onReceive(NotificationCenter.default.publisher(for: .sifSearch)) { _ in if libraryCommandsAvailable { searchFocused = true } }
        .onReceive(NotificationCenter.default.publisher(for: .sifRescan)) { _ in if !busy && iconEditor == nil && !showBackups && !showPermission { scan() } }
        .sheet(isPresented: $showBackups, onDismiss: {
            if chosenBackup != nil, requireClosedSafari() { confirmRestore = true }
            else { chosenBackup = nil }
        }) {
            BackupManagerView(root: store.backups, safariOpen: safariOpen) { url in
                chosenBackup = url; showBackups = false
            }
        }
        .sheet(item: $historySite) { item in
            VStack(alignment: .leading, spacing: 14) {
                Text(l10n("Historia ikony")).font(.title2.bold())
                Text(item.title).foregroundStyle(.secondary)
                if historyEntries.isEmpty { Text(l10n("Brak wcześniejszych grafik w kopiach zapasowych.")).padding(.vertical, 20) }
                else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(historyEntries) { version in
                                HStack(spacing: 12) {
                                    tile(version.png, fallback: item.title, size: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading) {
                                        Text(version.date, style: .date).font(.callout.weight(.medium))
                                        Text(version.date, style: .time).font(.caption).foregroundStyle(.secondary)
                                        if let style = version.style { Text(style.label).font(.caption2).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    Button(l10n("Przygotuj zmianę")) {
                                        if let (png, _) = safePNG(version.png) { stage(item, result: Pending(png: version.png.starts(with: [137,80,78,71,13,10,26,10]) ? version.png : png, source: l10n("Historia ikony"), custom: true, display: version.style)); historySite = nil }
                                    }.disabled(!item.registered || busy)
                                }.padding(9).background(surface, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }.frame(maxHeight: 310)
                }
                Text(l10n("Historia z lokalnych kopii zapasowych. Przywracasz tylko tę ikonę po zatwierdzeniu.")).font(.caption).foregroundStyle(.secondary)
                HStack { Spacer(); Button(l10n("Zamknij")) { historySite = nil }.keyboardShortcut(.cancelAction) }
            }.padding(24).frame(width: 470)
        }
        .quickLookPreview($nativePreviewURL)
        .onChange(of: nativePreviewURL) { current in
            if current == nil, let directory = nativePreviewDirectory {
                try? FileManager.default.removeItem(at: directory)
                nativePreviewDirectory = nil
            }
        }
        .sheet(item: $quickLook) { item in
            VStack(spacing: 16) {
                HStack(spacing: 20) {
                    VStack { safariTile(item, size: 150, after: false); Text(l10n("Przed")) }
                    VStack { safariTile(item, size: 150, after: true); Text(l10n("Po zmianie")) }
                }
                Text(item.title).font(.headline)
                Button(l10n("Zamknij")) { quickLook = nil }.keyboardShortcut(.defaultAction)
            }.padding(25)
        }
        .alert(l10n("Odrzucić przygotowane zmiany?"), isPresented: $confirmDiscard) {
            Button(l10n("Anuluj"), role: .cancel) {}
            Button(l10n("Odrzuć zmianę"), role: .destructive) { rememberDraft(); for host in scopedPending.keys { pending.removeValue(forKey: host); replacements.remove(host) } }
        } message: { Text(l10n("Zmiany w Safari pozostaną bez zmian. Odrzucisz tylko przygotowane ikony w tym zakresie.")) }
        .alert(l10n("Zastosować przygotowane ikony?"),isPresented:$confirm) { Button(l10n("Anuluj"),role:.cancel){}; Button(l10n("Zapisz"),action:write) } message: { Text(l10n("Zakres: {0}. Zapis: {1} ikon. Safari współdzieli ikony domen, więc zmiana może być widoczna również w innych folderach i poza Ulubionymi. Zamknij Safari przez ⌘Q. Przed zapisem powstanie kopia cache.", String(describing: scopeLabel), String(describing: scopedPending.count))) }
        .alert(l10n("Przywrócić domyślny wygląd {0} ikon?", String(describing: resetHosts.count)), isPresented: $confirmReset) {
            Button(l10n("Anuluj"), role: .cancel) {}
            Button(l10n("Przywróć domyślne"), role: .destructive, action: executeReset)
        } message: {
            Text(l10n("Usunie obecną grafikę i własne tło. Safari spróbuje pobrać domyślną ikonę; do tego czasu może wyświetlać literę. Dotyczy też wspólnych ikon w innych folderach. Zamknij Safari (⌘Q). Powstanie kopia. Zakładki pozostaną bez zmian."))
        }
        .alert(l10n("Przywrócić cały cache ikon?"),isPresented:$confirmRestore) { Button(l10n("Anuluj"),role:.cancel){}; Button(l10n("Przywróć"),role:.destructive) { guard !busy, requireClosedSafari() else { return }; if let saved = chosenBackup { chosenBackup = nil; do { let displaced = try store.restore(saved); pending = [:]; replacements = []; marked = []; undoPending = nil; runScan(presentPermission: true, completionMessage: l10n("Przywrócono kopię. Poprzedni cache: {0}.", String(describing: displaced.lastPathComponent))) } catch {handleOperationError(error)} } } } message: { Text(l10n("Wymaga zamknięcia Safari. Bieżący folder również zostanie zachowany jako kopia.") + (pending.isEmpty ? "" : "\n\n" + l10n("Przywrócenie całej kopii odrzuci przygotowane zmiany ({0}).", String(pending.count)))) }
    }
}
@MainActor private struct IconInteractionFeedback: ViewModifier {
    let selected: Bool
    let accent: Color
    let radius: CGFloat
    let onDrop: ([NSItemProvider]) -> Bool
    @State private var hovered = false
    @State private var targeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(targeted ? accent.opacity(0.22) : selected ? accent.opacity(0.14) : hovered && enabled ? Color.primary.opacity(0.045) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(targeted ? accent : selected ? accent.opacity(0.8) : Color.clear, lineWidth: targeted ? 2 : 1.2).allowsHitTesting(false))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $targeted) { providers in enabled && onDrop(providers) }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: targeted)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: selected)
    }
}
private enum StudioPreset: CaseIterable {
    case white, soft, midnight, amethyst
    var label: String { switch self { case .white: return "Original White"; case .soft: return "Soft Brand"; case .midnight: return "Midnight"; case .amethyst: return "Amethyst" } }
    var background: IconBackground { switch self { case .white: return .white; case .soft: return .automatic; default: return .custom } }
    var color: NSColor { switch self { case .white, .soft: return .white; case .midnight: return NSColor(srgbRed: 0.16, green: 0.15, blue: 0.19, alpha: 1); case .amethyst: return NSColor(srgbRed: 0.85, green: 0.78, blue: 0.98, alpha: 1) } }
}
@MainActor private struct InlineIconStudio: View {
    let data: Data
    let initialDisplay: SafariIconDisplay?
    let staged: Bool
    let changeImage: () -> Void
    let onStage: (Data, SafariIconDisplay) -> Bool
    private struct Input: Equatable { let data: Data; let style: SafariIconDisplay?; let staged: Bool }
    private var input: Input { Input(data: data, style: initialDisplay, staged: staged) }
    @State private var lastEmission: Input?
    @State private var art: IconArtwork?
    @State private var background: IconBackground = .original
    @State private var color: Color = .white
    @State private var inset = 0.12
    @State private var lightening = 0.40
    @State private var style = 0
    @State private var rendered: Data?
    @State private var edited = false
    @State private var advanced = false
    @State private var renderFailed = false
    @State private var selectedPreset: StudioPreset?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private func render() {
        guard let art, art.separate else { return }
        guard let result = composeArtwork(art, background: background, color: NSColor(color), inset: inset, lightening: lightening) else {
            renderFailed = true; return
        }
        renderFailed = false; rendered = result; edited = true
        stagePreview()
    }
    private func stagePreview() {
        let png = rendered ?? data
        let chosen = display
        if onStage(png, chosen) {
            lastEmission = Input(data: png, style: chosen, staged: true)
        } else { renderFailed = true }
    }
    private func resetInput() {
        art = IconArtwork(data); rendered = nil; edited = false; renderFailed = false
        background = .original; color = .white; lightening = 0.40; inset = 0.12; selectedPreset = nil
        if let art, art.separate { inset = max(0, min(0.30, (1 - Double(max(art.bounds.width, art.bounds.height)) / 256) / 2)) }
        style = initialDisplay.map { $0 == .fullTile ? 1 : 2 } ?? 0
        lastEmission = nil
    }
    private var display: SafariIconDisplay {
        if style == 1 { return .fullTile }; if style == 2 { return .systemTile }
        if !edited, let initialDisplay { return initialDisplay }
        return hasTransparentPixels(rendered ?? data) ? .systemTile : .fullTile
    }
    private func swatch(_ preset: StudioPreset) -> some View {
        let tint = preset == .soft ? Color(nsColor: nsColor((art?.dominant ?? IconRGB(r: 128, g: 128, b: 128)).lightened(lightening))) : Color(nsColor: preset.color)
        return Button {
            background = preset.background; color = Color(nsColor: preset.color); selectedPreset = preset; render()
        } label: {
            RoundedRectangle(cornerRadius: 8).fill(tint).frame(width: 29, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.14)))
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selectedPreset == preset ? Color.accentColor : Color.clear, lineWidth: 2))
        }.buttonStyle(.plain).help(preset.label).accessibilityLabel(preset.label)
            .accessibilityAddTraits(selectedPreset == preset ? .isSelected : [])
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selectedPreset)
    }
    private var preview: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 23, style: .continuous).fill(Color(white: 0.5))
                if let img = NSImage(data: rendered ?? data) {
                    Image(nsImage: img).resizable().scaledToFit()
                        .frame(width: display == .fullTile ? 104 : 86, height: display == .fullTile ? 104 : 86)
                }
            }.frame(width: 104, height: 104).clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 7, y: 3)
                .accessibilityLabel(l10n("Podgląd"))
            Button(action: changeImage) { Label(l10n("Zmień grafikę"), systemImage: "photo") }
                .buttonStyle(.bordered).controlSize(.regular)
        }.frame(maxWidth: .infinity).padding(.vertical, 17)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
    private var appearanceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n("Wygląd")).font(.callout.weight(.semibold))
            if art?.separate == true {
                HStack(spacing: 6) {
                    ForEach(StudioPreset.allCases, id: \.self) { preset in swatch(preset) }
                    ColorPicker(l10n("Własny kolor"), selection: Binding(get: { color }, set: { color = $0; background = .custom; selectedPreset = nil; render() }), supportsOpacity: false).labelsHidden()
                    Spacer(minLength: 0)
                }
                Picker(l10n("Tło"), selection: Binding(get: { background }, set: { background = $0; selectedPreset = nil; render() })) {
                    ForEach(IconBackground.allCases) { Text(l10n($0.rawValue)).tag($0) }
                }
                HStack { Text(l10n("Margines logo")); Spacer(); Text("\(Int(inset * 100))%").monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
                Slider(value: Binding(get: { inset }, set: { inset = $0; render() }), in: 0...0.30)
                    .accessibilityLabel(l10n("Margines logo"))
                if background == .automatic {
                    HStack { Text(l10n("Rozjaśnienie tła")); Spacer(); Text("\(Int(lightening * 100))%").monospacedDigit() }.font(.caption)
                    Slider(value: Binding(get: { lightening }, set: { lightening = $0; render() }), in: 0.30...0.50)
                        .accessibilityLabel(l10n("Rozjaśnienie tła"))
                }
            } else {
                Text(l10n("Złożone tło. Zachowuję cały obraz, aby nie tworzyć ostrych krawędzi.")).font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup(l10n("Styl w Safari"), isExpanded: $advanced) {
                Picker(l10n("Styl w Safari"), selection: Binding(get: { style }, set: { style = $0; edited = true; renderFailed = false; stagePreview() })) {
                    Text(l10n("Automatycznie")).tag(0); Text(l10n("Pełny kafelek")).tag(1); Text(l10n("Tło systemowe")).tag(2)
                }.labelsHidden().padding(.top, 5)
                Text(l10n("Pełny kafelek usuwa systemowy margines; automatycznie wybierany dla pełnego tła.")).font(.caption).foregroundStyle(.secondary)
            }.font(.caption)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            preview
            appearanceControls
            if renderFailed {
                Text(l10n("Nie udało się przygotować podglądu.")).font(.caption).foregroundStyle(.secondary)
            }
            if staged {
                Label(l10n("Gotowa do zapisania"), systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
                    .padding(.vertical, 5)
            }
            Text(l10n("Edycja trafia do szkicu. Zastosuj zapisze zmiany w Safari."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.onAppear { resetInput() }
        .onChange(of: input) { value in
            // Acknowledge our own edit without flattening artwork or resetting slider values.
            if value == lastEmission { lastEmission = nil } else { resetInput() }
        }
    }
}
@MainActor final class DraftProtection: NSObject, NSApplicationDelegate {
    static let shared = DraftProtection()
    var pending = 0
    var busy = false
    var flushDraft: (() -> Bool)?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let state = DraftProtection.shared
        if state.busy { return .terminateCancel }
        let saved = state.flushDraft?() ?? (state.pending == 0)
        guard state.pending > 0 else { return .terminateNow }
        if saved { return .terminateNow }
        let alert = NSAlert(); alert.messageText = l10n("Zakończyć z przygotowanymi ikonami?")
        alert.informativeText = l10n("Nie udało się zachować szkicu na dysku. Zakończenie może spowodować utratę przygotowanych zmian.")
        alert.addButton(withTitle: l10n("Anuluj")); alert.addButton(withTitle: l10n("Zakończ"))
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
extension Notification.Name {
    static let sifUndoDraft = Notification.Name("SIF.UndoDraft")
    static let sifSelectAll = Notification.Name("SIF.SelectAll")
    static let sifQuickLook = Notification.Name("SIF.QuickLook")
    static let sifCompare = Notification.Name("SIF.Compare")
    static let sifSearch = Notification.Name("SIF.Search")
    static let sifRescan = Notification.Name("SIF.Rescan")
}
@main struct SafariIconFixerApp: App {
    @NSApplicationDelegateAdaptor(DraftProtection.self) private var appDelegate
    @StateObject private var updates = AppUpdates.shared
    var body: some Scene {
        Window("Safari Icon Fixer", id: "main") { MainView() }.defaultSize(width: 1120, height: 680).windowResizability(.contentMinSize)
            .commands {
                CommandMenu(l10n("Ikony")) {
                    Button(l10n("Cofnij przygotowaną zmianę")) { NotificationCenter.default.post(name: .sifUndoDraft, object: nil) }.keyboardShortcut("z", modifiers: [.command, .option])
                    Button(l10n("Zaznacz widoczne")) { NotificationCenter.default.post(name: .sifSelectAll, object: nil) }.keyboardShortcut("a", modifiers: [.command, .shift])
                    Divider()
                    Button(l10n("Szybki podgląd")) { NotificationCenter.default.post(name: .sifQuickLook, object: nil) }.keyboardShortcut("y", modifiers: [.command])
                    Button(l10n("Porównaj przed i po")) { NotificationCenter.default.post(name: .sifCompare, object: nil) }.keyboardShortcut("y", modifiers: [.command, .shift])
                    Divider()
                    Button(l10n("Szukaj strony…")) { NotificationCenter.default.post(name: .sifSearch, object: nil) }.keyboardShortcut("f", modifiers: [.command])
                    Button(l10n("Przeskanuj Ulubione")) { NotificationCenter.default.post(name: .sifRescan, object: nil) }.keyboardShortcut("r", modifiers: [.command])
                }
                CommandMenu(l10n("Język")) {
                    ForEach(AppLanguage.choices, id: \.code) { choice in
                        Button {
                            AppLanguage.set(choice.code)
                            let alert = NSAlert()
                            alert.messageText = l10n("Wybrano język")
                            alert.informativeText = l10n("Język zostanie zmieniony po ponownym uruchomieniu aplikacji.")
                            alert.addButton(withTitle: l10n("OK"))
                            alert.runModal()
                        } label: {
                            if AppLanguage.selection == choice.code {
                                Label(choice.code == "system" ? l10n("Automatycznie (system)") : choice.name, systemImage: "checkmark")
                            } else {
                                Text(choice.code == "system" ? l10n("Automatycznie (system)") : choice.name)
                            }
                        }
                    }
                }
                CommandGroup(replacing: .appInfo) {
                    Button(l10n("O Safari Icon Fixer")) { NotificationCenter.default.post(name: .sifAbout, object: nil) }
                    Button(l10n("Sprawdź aktualizacje…")) { updates.check() }.disabled(!updates.canCheck)
                }
            }
    }
}
