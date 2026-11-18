import Foundation
import AppKit

struct HistoricalIcon: Identifiable {
    let id: String
    let date: Date
    let png: Data
    let style: SafariIconDisplay?
}
struct Cache {
    static let fm = FileManager.default
    let safari: URL
    private let supportRoot: URL?
    private let runningOverride: (() -> Bool)?
    private let fault: ((String) throws -> Void)?
    init(safari: URL, supportRoot: URL? = nil, runningOverride: (() -> Bool)? = nil, fault: ((String) throws -> Void)? = nil) {
        self.safari = safari; self.supportRoot = supportRoot; self.runningOverride = runningOverride; self.fault = fault
    }
    var journal: RecoveryJournal { RecoveryJournal(root: backups.deletingLastPathComponent()) }
    var cache: URL { safari.appendingPathComponent("Touch Icons Cache", isDirectory: true) }
    var db: URL { cache.appendingPathComponent("TouchIconCacheSettings.db") }
    var images: URL { cache.appendingPathComponent("Images", isDirectory: true) }
    var backups: URL { (supportRoot ?? Cache.fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Safari Icon Fixer", isDirectory: true)).appendingPathComponent("Backups", isDirectory: true) }
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
        try journal.withLock {
            try requireNoRecovery()
            return try captureKnownIconsLocked(sites)
        }
    }
    private func captureKnownIconsLocked(_ sites: [Site]) throws -> PersonalizationState {
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
    var safariRunning: Bool { runningOverride?() ?? NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Safari" || $0.bundleIdentifier == "com.apple.SafariTechnologyPreview" } }
    func icon(_ host: String) -> URL { images.appendingPathComponent(hash(host) + ".png") }
    private func layout(in directory: URL) throws -> SafariCacheLayout {
        try RecoveryJournal.directory(directory)
        try RecoveryJournal.directory(directory.appendingPathComponent("Images"))
        let database = directory.appendingPathComponent("TouchIconCacheSettings.db")
        try RecoveryJournal.regular(database)
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecar = URL(fileURLWithPath: database.path + suffix)
            if RecoveryJournal.exists(sidecar) { try RecoveryJournal.regular(sidecar) }
        }
        let cols = Set(try rows(database, "PRAGMA table_info(cache_settings);").compactMap { $0["name"] as? String })
        guard let result = SafariCacheLayout(columns: cols) else { throw fail(l10n("Nieznany schemat cache Safari. Zapis jest zablokowany.")) }
        return result
    }
    func schema() throws -> String {
        try RecoveryJournal.directory(safari)
        return try layout(in: cache).flag
    }
    func hasDisplayColumn() throws -> Bool { try layout(in: cache).hasDisplay }
    private func validateSnapshot(_ directory: URL) throws {
        _ = try layout(in: directory)
        let database = directory.appendingPathComponent("TouchIconCacheSettings.db")
        let check = try rows(database, "PRAGMA quick_check;")
        guard check.count == 1, check[0]["quick_check"] as? String == "ok" else { throw fail(l10n("Kopia cache jest uszkodzona lub niekompatybilna.")) }
        // Reject symlinks, special files, and corrupt personalization before any live mutation.
        try RecoveryJournal.syncTree(directory)
        let metadata = directory.appendingPathComponent(snapshotMetadata)
        if RecoveryJournal.exists(metadata) {
            let state = try PersonalizationFile.read(metadata)
            guard state.icons.allSatisfy({ host, icon in state.registry[host] == iconDigest(icon.png) && cachedIconSize(icon.png) != nil }) else {
                throw fail(l10n("Kopia cache jest uszkodzona lub niekompatybilna."))
            }
        }
    }
    private func compatibleSnapshot(_ saved: URL) throws {
        try validateSnapshot(saved)
        let other = saved.appendingPathComponent("TouchIconCacheSettings.db")
        // Strict native SQLite schema comparison, not an inferred Safari version.
        let query = "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name;"
        let version = "PRAGMA user_version;"
        guard try layout(in: saved) == layout(in: cache),
              try sql(other, query) == sql(db, query), try sql(other, version) == sql(db, version) else {
            throw fail(l10n("Kopia cache jest uszkodzona lub niekompatybilna."))
        }
    }
    private func requireNoRecovery() throws {
        guard try journal.read() == nil else { throw fail(l10n("Wykryto przerwany zapis. Zamknij Safari i przeskanuj ponownie, aby odzyskać cache.")) }
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
        try requireNoRecovery()
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
        try RecoveryJournal.directory(backups)
        let id = UUID().uuidString
        let dest = backups.appendingPathComponent(id, isDirectory: true)
        let partial = backups.appendingPathComponent(".partial-" + id, isDirectory: true)
        defer { try? Cache.fm.removeItem(at: partial) }
        try Cache.fm.copyItem(at: cache, to: partial)
        try PersonalizationFile.write(personalization, to: partial.appendingPathComponent(snapshotMetadata))
        try validateSnapshot(partial)
        guard !safariRunning else { throw fail(l10n("Safari zostało otwarte podczas przygotowania.")) }
        let now = Date(); try? Cache.fm.setAttributes([.creationDate: now, .modificationDate: now], ofItemAtPath: partial.path)
        try RecoveryJournal.sync(partial)
        try Cache.fm.moveItem(at: partial, to: dest)
        try RecoveryJournal.sync(backups)
        return dest
    }
    private func completeTransaction() throws {
        guard !safariRunning else { throw fail(l10n("Safari zostało otwarte podczas zapisu.")) }
        // Do not clear the marker until PNGs, database and personalization are durable.
        try RecoveryJournal.syncTree(cache)
        if RecoveryJournal.exists(personalizationURL) { try RecoveryJournal.sync(personalizationURL) }
        try RecoveryJournal.sync(safari)
        try RecoveryJournal.sync(journal.root)
        guard !safariRunning else { throw fail(l10n("Safari zostało otwarte podczas zapisu.")) }
        try journal.finish()
    }
    func apply(_ pending: [String: Pending], allowingReplacement: Set<String>, scope: FavoriteScope) throws -> (URL, Int) {
        try journal.withLock {
            try requireNoRecovery()
            return try applyLocked(pending, allowingReplacement: allowingReplacement, scope: scope)
        }
    }
    private func applyLocked(_ pending: [String: Pending], allowingReplacement: Set<String>, scope: FavoriteScope) throws -> (URL, Int) {
        guard !pending.isEmpty, !safariRunning else { throw fail(l10n("Zamknij Safari (⌘Q) i przygotuj ikony.")) }
        let flag = try schema(); let current = try scan().sites; let byHost = Dictionary(uniqueKeysWithValues: current.map { ($0.host, $0) })
        for (host, item) in pending {
            guard let site = byHost[host], site.locations.contains(where: { scope.includes($0.folder) }), site.registered, site.existing == nil || allowingReplacement.contains(host) || (site.needsRepair && site.existing == item.png) else { throw fail(l10n("Stan {0} uległ zmianie lub rekord nie istnieje. Przeskanuj ponownie.", String(describing: host))) }
            if let expected = item.expectedDigest, site.existing.map(iconDigest) != expected { throw fail(l10n("Ikona {0} zmieniła się od przygotowania. Przeskanuj i ponów.", String(describing: host))) }
            if RecoveryJournal.exists(icon(host)) { try RecoveryJournal.regular(icon(host)) }
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
        let saved = try backup(oldState); try journal.begin(snapshot: saved)
        do {
            guard !safariRunning else { throw fail(l10n("Safari zostało otwarte podczas przygotowania.")) }
            for (host, item) in pending {
                guard !safariRunning else { throw fail(l10n("Safari zostało otwarte podczas zapisu.")) }
                if byHost[host]?.existing != item.png { try item.png.write(to: icon(host), options: .atomic) }; try fault?("image-written")
            }
            guard !safariRunning else { throw fail(l10n("Safari zostało otwarte podczas zapisu.")) }
            if oldState != nextState { try savePersonalization(nextState) }; try fault?("personalization-written")
            guard !safariRunning else { throw fail(l10n("Safari zostało otwarte podczas zapisu.")) }
            let statements = pending.keys.sorted().map { host -> String in
                let assignment = iconDisplayAssignment(pending[host]?.display)
                return "UPDATE cache_settings SET \(flag)=1, download_status_flags=1\(assignment) WHERE host=\(quote(host));"
            }.joined(separator: "\n")
            _ = try sql(db, "BEGIN IMMEDIATE;\n" + statements + "\nCOMMIT;", write: true)
            try fault?("database-committed")
        } catch {
            throw fail(l10n("Zapis przerwany: {0}. Kopia: {1}", error.localizedDescription, saved.path) + " " + l10n("Wykryto przerwany zapis. Zamknij Safari i przeskanuj ponownie, aby odzyskać cache."))
        }
        try completeTransaction()
        return (saved, pending.count)
    }
    func reset(_ hosts: Set<String>, scope: FavoriteScope, trackedOnly: Bool) throws -> URL {
        try journal.withLock {
            try requireNoRecovery()
            return try resetLocked(hosts, scope: scope, trackedOnly: trackedOnly)
        }
    }
    private func resetLocked(_ hosts: Set<String>, scope: FavoriteScope, trackedOnly: Bool) throws -> URL {
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
        try journal.begin(snapshot: saved)
        do {
            for host in hosts.sorted() {
                guard !safariRunning else { throw fail(l10n("Safari zostało otwarte podczas resetu.")) }
                let path = icon(host)
                if Cache.fm.fileExists(atPath: path.path) { try Cache.fm.removeItem(at: path) }; try fault?("image-removed")
            }
            if nextState != oldState { try savePersonalization(nextState) }; try fault?("personalization-written")
            guard !safariRunning else { throw fail(l10n("Safari zostało otwarte podczas resetu.")) }
            let statements = hosts.sorted().map { "UPDATE cache_settings SET \(flag)=0, download_status_flags=0 WHERE host=\(quote($0));" }.joined(separator: "\n")
            _ = try sql(db, "BEGIN IMMEDIATE;\n" + statements + "\nCOMMIT;", write: true)
            try fault?("database-committed")
        } catch {
            throw fail(l10n("Reset przerwany: {0}. Kopia: {1}", error.localizedDescription, saved.path) + " " + l10n("Wykryto przerwany zapis. Zamknij Safari i przeskanuj ponownie, aby odzyskać cache."))
        }
        try completeTransaction()
        return saved
    }
    func restore(_ saved: URL) throws -> URL {
        try journal.withLock {
            try requireNoRecovery()
            guard !safariRunning else { throw fail(l10n("Zamknij Safari (⌘Q).")) }
            _ = try schema()
            try RecoveryJournal.directory(backups)
            guard saved.deletingLastPathComponent().standardizedFileURL.path == backups.standardizedFileURL.path,
                  UUID(uuidString: saved.lastPathComponent) != nil else { throw fail(l10n("Wybierz prawidłową kopię aplikacji.")) }
            try compatibleSnapshot(saved)
            let oldState = try personalization()
            let previous = try backup(oldState)
            try journal.begin(snapshot: previous)
            let displaced = try installSnapshot(saved, fallback: oldState)
            try completeTransaction()
            if let displaced { try? Cache.fm.removeItem(at: displaced) }
            return previous
        }
    }
    // A confirmed recovery always restarts from the same protected snapshot. If interrupted
    // again, the journal remains. Preserve any displaced cache, including after Safari reopened.
    func recoverInterruptedWrite() throws {
        try journal.withLock {
            guard let record = try journal.read() else { return }
            guard !safariRunning else { throw fail(l10n("Zamknij Safari (⌘Q).")) }
            try RecoveryJournal.directory(backups)
            let saved = journal.snapshot(record)
            try validateSnapshot(saved)
            // Never replace a readable but incompatible cache after a Safari schema upgrade.
            // A missing/unreadable database can itself be the result of interrupted restore.
            if RecoveryJournal.exists(cache) {
                try RecoveryJournal.directory(cache)
                if RecoveryJournal.exists(db) {
                    try RecoveryJournal.regular(db)
                    for suffix in ["-wal", "-shm", "-journal"] {
                        let sidecar = URL(fileURLWithPath: db.path + suffix)
                        if RecoveryJournal.exists(sidecar) { try RecoveryJournal.regular(sidecar) }
                    }
                    if (try? rows(db, "PRAGMA schema_version;")) != nil { try compatibleSnapshot(saved) }
                }
            }
            let metadata = saved.appendingPathComponent(snapshotMetadata)
            let state = try PersonalizationFile.read(metadata)
            _ = try installSnapshot(saved, fallback: state)
            try completeTransaction()
        }
    }
    private func installSnapshot(_ saved: URL, fallback: PersonalizationState) throws -> URL? {
        guard !safariRunning else { throw fail(l10n("Zamknij Safari (⌘Q).")) }
        try RecoveryJournal.directory(safari)
        try validateSnapshot(saved)
        let metadata = saved.appendingPathComponent(snapshotMetadata)
        let restored = RecoveryJournal.exists(metadata) ? try PersonalizationFile.read(metadata) : fallback
        let artifacts = journal.root.appendingPathComponent("RecoveryArtifacts", isDirectory: true)
        try Cache.fm.createDirectory(at: artifacts, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try RecoveryJournal.directory(artifacts)
        let staged = artifacts.appendingPathComponent(".stage-" + UUID().uuidString)
        let displaced = artifacts.appendingPathComponent("Displaced-" + UUID().uuidString)
        defer { try? Cache.fm.removeItem(at: staged) }
        try Cache.fm.copyItem(at: saved, to: staged)
        let sidecar = staged.appendingPathComponent(snapshotMetadata)
        if RecoveryJournal.exists(sidecar) { try Cache.fm.removeItem(at: sidecar) }
        try RecoveryJournal.syncTree(staged)
        try RecoveryJournal.sync(artifacts)
        guard !safariRunning else { throw fail(l10n("Safari zostało otwarte.")) }
        if RecoveryJournal.exists(cache) {
            try RecoveryJournal.directory(cache)
            try Cache.fm.moveItem(at: cache, to: displaced)
            try RecoveryJournal.sync(artifacts); try RecoveryJournal.sync(safari)
            try fault?("cache-displaced")
        }
        guard !safariRunning else { throw fail(l10n("Safari zostało otwarte.")) }
        // A re-opened Safari may have created a new directory; never overwrite it.
        try Cache.fm.moveItem(at: staged, to: cache)
        try fault?("cache-installed")
        guard !safariRunning else { throw fail(l10n("Safari zostało otwarte.")) }
        try savePersonalization(restored)
        try fault?("personalization-written")
        return RecoveryJournal.exists(displaced) ? displaced : nil
    }
}
