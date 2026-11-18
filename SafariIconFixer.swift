import SwiftUI
import Combine
import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

struct FixError: LocalizedError { let message: String; var errorDescription: String? { message } }
func fail(_ s: String) -> FixError { FixError(message: s) }
struct Site: Identifiable {
    var id: String { host }; let host: String; var names: [String]; let locations: [FavoriteLink]; let registered: Bool; let existing: Data?; let active: Bool; let downloadFlags: Int?; let pixelSize: Int?
    var title: String { names.joined(separator: " · ") }
    var needsRepair: Bool { !registered || existing == nil || !active || downloadFlags != 1 }
    var status: String {
        if !registered { return "Brak rekordu" }
        if existing == nil { return "Brak ikony" }
        if !active { return "Ikona nieaktywna" }
        if downloadFlags != 1 { return "Status do sprawdzenia" }
        return "W cache" // This is not proof of rendering in Safari.
    }
}
struct Pending { let png: Data; let source: String }

func hash(_ host: String) -> String { Insecure.MD5.hash(data: Data(host.utf8)).map { String(format: "%02X", $0) }.joined() }
func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "''") + "'" }
func sql(_ db: URL, _ query: String, write: Bool = false) throws -> Data {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    p.arguments = ["-bail", "-init", "/dev/null"] + (write ? [] : ["-readonly", "-json"]) + [db.path, ".timeout 3000", query]
    let output = Pipe(); let error = Pipe(); p.standardOutput = output; p.standardError = error
    try p.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); let err = error.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw fail(String(data: err, encoding: .utf8) ?? "Błąd SQLite") }; return data
}
func rows(_ db: URL, _ query: String) throws -> [[String: Any]] {
    let data = try sql(db, query); if data.isEmpty { return [] }
    guard let result = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw fail("Nierozpoznany wynik SQLite.") }; return result
}
func safePNG(_ data: Data) -> (Data, Int)? {
    guard data.count <= 8_000_000, let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    var best = 0; var score = 0
    for i in 0..<min(CGImageSourceGetCount(src), 32) {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [String: Any], let w = props[kCGImagePropertyPixelWidth as String] as? Int, let h = props[kCGImagePropertyPixelHeight as String] as? Int, w > 0, h > 0, w <= 8192, h <= 8192 else { continue }
        if min(w,h) > score { score = min(w,h); best = i }
    }
    guard score > 0, let image = CGImageSourceCreateThumbnailAtIndex(src, best, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary), let ctx = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let scale = 256 / CGFloat(max(image.width, image.height)); let w = CGFloat(image.width)*scale, h = CGFloat(image.height)*scale
    ctx.interpolationQuality = .high; ctx.draw(image, in: CGRect(x: (256-w)/2, y: (256-h)/2, width: w, height: h))
    guard let rendered = ctx.makeImage() else { return nil }; let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }; CGImageDestinationAddImage(dest, rendered, nil); guard CGImageDestinationFinalize(dest) else { return nil }; return (out as Data, score)
}

struct Cache {
    static let fm = FileManager.default
    let safari: URL
    var cache: URL { safari.appendingPathComponent("Touch Icons Cache", isDirectory: true) }
    var db: URL { cache.appendingPathComponent("TouchIconCacheSettings.db") }
    var images: URL { cache.appendingPathComponent("Images", isDirectory: true) }
    var backups: URL { Cache.fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Safari Icon Fixer/Backups", isDirectory: true) }
    var safariRunning: Bool { NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Safari" || $0.bundleIdentifier == "com.apple.SafariTechnologyPreview" } }
    func icon(_ host: String) -> URL { images.appendingPathComponent(hash(host) + ".png") }
    func schema() throws -> String {
        for path in [safari, cache, images, db] {
            let v = try path.resourceValues(forKeys: [.isSymbolicLinkKey]); guard v.isSymbolicLink != true else { throw fail("Nieobsługiwana ścieżka symboliczna: \(path.path)") }
        }
        let cols = Set(try rows(db,"PRAGMA table_info(cache_settings);").compactMap { $0["name"] as? String })
        guard cols.contains("host"), cols.contains("download_status_flags"), let flag = ["touch_icon_is_in_cache", "icon_is_in_cache"].first(where: {cols.contains($0)}) else { throw fail("Nieznany schemat cache Safari. Zapis jest zablokowany.") }
        return flag
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
        guard let root = obj as? [String: Any] else { throw fail("Nieznany format zakładek.") }
        let index = try FavoritesIndex(root: root)
        let named = Dictionary(grouping: index.links, by: \.host)
        let dbRows = try rows(db, "SELECT host, \(flag) AS active, download_status_flags AS download_flags FROM cache_settings;")
        var registered: [String: [Int]] = [:]
        var downloadFlags: [String: Int] = [:]
        for row in dbRows {
            if let h = row["host"] as? String {
                registered[h,default: []].append(row["active"] as? Int ?? 0)
                downloadFlags[h] = row["download_flags"] as? Int
            }
        }
        var sites: [Site] = []
        for (host, links) in named {
            let url: URL = icon(host)
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
            var existing: Data? = nil
            var pixelSize: Int? = nil
            if values?.isSymbolicLink != true {
                if let data = try? Data(contentsOf: url), let (_, size) = safePNG(data) {
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
                            downloadFlags: downloadFlags[host], pixelSize: pixelSize)
            sites.append(site)
        }
        sites.sort { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return (sites, index.folders)
    }
    func backup() throws -> URL {
        guard !safariRunning else { throw fail("Zamknij Safari (⌘Q), a następnie ponów.") }
        try Cache.fm.createDirectory(at: backups, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let dest = backups.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try Cache.fm.copyItem(at: cache, to: dest); return dest
    }
    func apply(_ pending: [String: Pending], allowingReplacement: Set<String>, scope: FavoriteScope) throws -> (URL, Int) {
        guard !pending.isEmpty, !safariRunning else { throw fail("Zamknij Safari (⌘Q) i przygotuj ikony.") }
        let flag = try schema(); let current = try scan().sites; let byHost = Dictionary(uniqueKeysWithValues: current.map { ($0.host, $0) })
        for (host, item) in pending {
            guard let site = byHost[host], site.locations.contains(where: { scope.includes($0.folder) }), site.registered, site.existing == nil || allowingReplacement.contains(host) || (site.needsRepair && site.existing == item.png) else { throw fail("Stan \(host) uległ zmianie lub rekord nie istnieje. Przeskanuj ponownie.") }
            if Cache.fm.fileExists(atPath: icon(host).path), try icon(host).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw fail("Odmowa zapisu do dowiązania symbolicznego.") }
        }
        guard current.contains(where: { $0.registered && $0.existing != nil && $0.active }) else { throw fail("Nie potwierdzono mapowania nazw plików MD5 dla tej wersji Safari. Zapis zablokowany.") }
        let saved = try backup(); var changed: [String] = []
        do {
            guard !safariRunning else { throw fail("Safari zostało otwarte podczas przygotowania.") }
            for (host, item) in pending {
                guard !safariRunning else { throw fail("Safari zostało otwarte podczas zapisu.") }
                if byHost[host]?.existing != item.png { changed.append(host); try item.png.write(to: icon(host), options: .atomic) }
            }
            guard !safariRunning else { throw fail("Safari zostało otwarte podczas zapisu.") }
            let statements = pending.keys.sorted().map { "UPDATE cache_settings SET \(flag)=1, download_status_flags=1 WHERE host=\(quote($0));" }.joined(separator: "\n")
            _ = try sql(db, "BEGIN IMMEDIATE;\n" + statements + "\nCOMMIT;", write: true)
            return (saved, pending.count)
        } catch {
            var problems: [String] = []
            for host in changed {
                let before = saved.appendingPathComponent("Images").appendingPathComponent(hash(host)+".png")
                do { if Cache.fm.fileExists(atPath: before.path) { try Data(contentsOf: before).write(to: icon(host), options: .atomic) } else if Cache.fm.fileExists(atPath: icon(host).path) { try Cache.fm.removeItem(at: icon(host)) } } catch { problems.append(host) }
            }
            throw fail("Zapis przerwany: \(error.localizedDescription). Kopia: \(saved.path)" + (problems.isEmpty ? "" : " Nie udało się odtworzyć: \(problems.joined(separator: ", "))"))
        }
    }
    func restore(_ saved: URL) throws -> URL {
        _ = try schema()
        guard !safariRunning else { throw fail("Zamknij Safari (⌘Q).") }
        guard saved.deletingLastPathComponent().standardizedFileURL == backups.standardizedFileURL, UUID(uuidString: saved.lastPathComponent) != nil, Cache.fm.fileExists(atPath: saved.appendingPathComponent("TouchIconCacheSettings.db").path) else { throw fail("Wybierz prawidłową kopię aplikacji.") }
        guard !safariRunning else { throw fail("Zamknij Safari.") }
        let staged = safari.appendingPathComponent("SIF-stage-\(UUID().uuidString)"); let displaced = backups.appendingPathComponent(UUID().uuidString)
        try Cache.fm.copyItem(at: saved, to: staged)
        defer { try? Cache.fm.removeItem(at: staged) }
        guard !safariRunning else { throw fail("Safari zostało otwarte.") }
        try Cache.fm.moveItem(at: cache, to: displaced)
        do { try Cache.fm.moveItem(at: staged, to: cache) } catch {
            do { try Cache.fm.moveItem(at: displaced, to: cache) } catch { throw fail("Nie udało się odtworzyć bieżącej pamięci. Zachowano ją w \(displaced.path).") }; throw error
        }
        return displaced
    }
}

final class SameHost: NSObject, URLSessionTaskDelegate {
    let host: String; init(_ host: String) { self.host = host }
    func accepts(_ url: URL) -> Bool { guard url.scheme == "https", let h = url.host?.lowercased(), url.user == nil, url.password == nil else { return false }; return h == host || h == "www." + host || (host.hasPrefix("www.") && h == String(host.dropFirst(4))) }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(request.url.map(accepts) == true ? request : nil) }
}
func fetchIcon(_ host: String) async -> Pending? {
    guard let root = URL(string: "https://\(host)/") else { return nil }
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
    var seen = Set<URL>(); var best: (Pending,Int)?
    for url in candidates.filter({seen.insert($0).inserted}).prefix(5) {
        if let (data, final) = await get(url, limit: 8_000_000), let (png, size) = safePNG(data), size > (best?.1 ?? 0) { best = (Pending(png:png, source:final.absoluteString), size); if size >= 180 { break } }
    }
    return best?.0
}

@MainActor struct MainView: View {
    @State private var store = Cache(safari: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari"))
    @State private var sites: [Site] = []; @State private var pending: [String: Pending] = [:]; @State private var replacements = Set<String>()
    @State private var marked = Set<String>()
    @State private var folders: [FavoriteFolder] = []; @State private var scope: FavoriteScope = .root
    @State private var selected: String?; @State private var filter = "Wszystkie"; @State private var search = ""; @State private var message = "Przeskanuj Ulubione Safari. Nic nie zostanie zmienione."; @State private var busy = false; @State private var confirm = false; @State private var confirmRestore = false; @State private var chosenBackup: URL?
    @State private var permissionDenied = false
    @State private var showPermission = false
    @State private var waitingForPermission = false
    @State private var permissionHelp = ""
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
    var shown: [Site] { scoped.filter { s in (filter == "Wszystkie" || (filter == "Brakujące" && s.needsRepair) || (filter == "Gotowe" && pending[s.host] != nil)) && (search.isEmpty || (s.title + s.host).localizedCaseInsensitiveContains(search)) } }
    var missing: [Site] { scoped.filter { $0.registered && $0.needsRepair && pending[$0.host] == nil } }
    var markedSites: [Site] { scoped.filter { marked.contains($0.host) && $0.registered } }
    var scopedPending: [String: Pending] { pending.filter { pair in scoped.contains { $0.host == pair.key } } }
    var site: Site? { shown.first { $0.host == selected } }
    var scopeLabel: String { switch scope { case .all: return "Wszystkie Ulubione"; case .root: return "Bez folderu"; case .folder: return folders.first { $0.scope == scope }?.label ?? "Folder" } }
    func openPrivacySettings() {
        waitingForPermission = true
        permissionHelp = "Włącz dostęp dla Safari Icon Fixer, a następnie wróć tutaj. Jeśli dostęp nadal nie działa, zamknij aplikację (⌘Q) i uruchom ją ponownie."
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"), NSWorkspace.shared.open(url) { return }
        if let url = URL(string: "x-apple.systempreferences:") { _ = NSWorkspace.shared.open(url) }
        permissionHelp = "Otwórz Prywatność i ochrona → Pełny dostęp do dysku. Jeśli ustawienia nie otworzyły się automatycznie, uruchom je z menu Apple."
    }
    func reportPermission(_ error: Error, present: Bool = true) {
        permissionDenied = true
        if present { showPermission = true }
        message = "Brak dostępu do danych Safari: \(error.localizedDescription)"
        permissionHelp = "Jeśli dostęp jest już włączony, zamknij aplikację (⌘Q) i uruchom ją ponownie."
    }
    func handleOperationError(_ error: Error) {
        if isSafariPermissionError(error) { reportPermission(error) }
        else { message = error.localizedDescription }
    }
    func scan() { runScan(presentPermission: true) }
    func runScan(presentPermission: Bool) {
        guard !busy else { return }
        do {
            let result = try store.scan(); sites = result.sites; folders = result.folders
            if case .folder = scope, !folders.contains(where: { $0.scope == scope }) { scope = .root }
            let hosts = Set(sites.map(\.host)); pending = pending.filter { hosts.contains($0.key) }; replacements.formIntersection(hosts); marked.formIntersection(hosts)
            permissionDenied = false; showPermission = false; waitingForPermission = false; permissionHelp = ""
            message = "Odczytano \(sites.count) domen w Ulubionych. W wybranym zakresie: \(scoped.count)."
        } catch {
            sites = []; folders = []; selected = nil
            if isSafariPermissionError(error) {
                reportPermission(error, present: presentPermission)
            } else {
                permissionDenied = false; showPermission = false; waitingForPermission = false
                pending = [:]; replacements = []; marked = []; scope = .root
                message = "Nie można odczytać Safari: \(error.localizedDescription)"
            }
        }
    }
    func prepare() { prepareSites(missing) }
    func prepareMarked() { prepareSites(markedSites) }
    func prepareSites(_ targets: [Site]) {
        guard !busy, !permissionDenied, !targets.isEmpty else { return }
        busy = true
        Task {
            var failures = 0
            for (i, site) in targets.enumerated() {
                message = "Przygotowanie \(i+1)/\(targets.count): \(site.host)"
                guard site.registered else { failures += 1; continue }
                if let existing = site.existing, let (png, _) = safePNG(existing) {
                    pending[site.host] = Pending(png: png, source: "Ikona z cache — ponowny zapis PNG 256 × 256 i aktywacja")
                    replacements.insert(site.host)
                } else if let p = await fetchIcon(site.host) {
                    pending[site.host] = p
                    if site.existing != nil { replacements.insert(site.host) }
                } else { failures += 1 }
            }
            busy = false
            message = "Przygotowano \(scopedPending.count) ikon w zakresie. Nie zmieniono Safari. Niepowodzenia: \(failures)."
        }
    }
    func toggleMarked(_ host: String, _ value: Bool) {
        if value { marked.insert(host) } else { marked.remove(host) }
    }
    func siteRow(_ site: Site) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { marked.contains(site.host) }, set: { toggleMarked(site.host, $0) }))
                .toggleStyle(.checkbox).labelsHidden().disabled(busy || !site.registered)
                .help("Zaznacz do wymuszonej naprawy")
            tile(site.existing, fallback: site.title, size: 36)
            VStack(alignment: .leading) {
                Text(site.title).lineLimit(1)
                Text(site.host).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(pending[site.host] != nil ? "Gotowa" : site.status)
                .font(.caption).foregroundStyle(pending[site.host] != nil ? Color.green : Color.secondary)
        }
    }
    func cacheDetails(_ site: Site) -> String {
        let flags = site.downloadFlags.map { String($0) } ?? "brak"
        let size = site.pixelSize.map { "\($0) px" } ?? "brak"
        return "Cache: \(size) · aktywna: \(site.active ? "tak" : "nie") · status: \(flags)"
    }
    func choose(_ s: Site) { let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.canChooseDirectories = false; guard panel.runModal() == .OK, let url = panel.url else { return }; do { let data = try Data(contentsOf: url); guard let (png,_) = safePNG(data) else { throw fail("Nieobsługiwany lub uszkodzony obraz (limit 8 MB).") }; pending[s.host] = Pending(png: png,source:url.lastPathComponent); if s.existing != nil { replacements.insert(s.host) }; message = "Przygotowano własną ikonę. Zmiana wymaga zatwierdzenia." } catch { message = error.localizedDescription } }
    func write() {
        guard !permissionDenied else { showPermission = true; return }
        let batch = scopedPending
        do {
            let (backup,count) = try store.apply(batch,allowingReplacement:replacements,scope:scope)
            for host in batch.keys { pending.removeValue(forKey:host); replacements.remove(host); marked.remove(host) }
            scan(); message = "Zapisano \(count) ikon. Kopia: \(backup.lastPathComponent). Otwórz Safari i sprawdź efekt."
        } catch { handleOperationError(error) }
    }
    func selectBackup() { let p = NSOpenPanel(); p.directoryURL = store.backups; p.canChooseDirectories = true; p.canChooseFiles = false; guard p.runModal() == .OK, let u = p.url else {return}; chosenBackup = u; confirmRestore = true }
    func tile(_ data: Data?, fallback: String, size: CGFloat) -> some View { Group { if let data, let image = NSImage(data:data) { Image(nsImage:image).resizable().scaledToFit() } else { ZStack { RoundedRectangle(cornerRadius:size*0.22).fill(.gray.opacity(0.2)); Text(fallback.prefix(1).uppercased()).font(.system(size:size*0.45,weight:.medium)).foregroundStyle(.secondary) } } }.frame(width:size,height:size) }
    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Safari Icon Fixer").font(.title2.bold())
                    Text("Ulubione · lokalna naprawa ikon").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button("Skanuj", action: scan).disabled(busy)
                Button("Pobierz brakujące", action: prepare).disabled(busy || permissionDenied || missing.isEmpty)
                Button("Zastosuj (\(scopedPending.count))") { confirm = true }
                    .buttonStyle(.borderedProminent).disabled(busy || permissionDenied || scopedPending.isEmpty)
            }
            HStack(spacing: 16) {
                Text("\(scoped.count) domen")
                Text("\(scoped.filter { $0.existing != nil }.count) w cache")
                Text("\(scoped.filter { $0.needsRepair }.count) do sprawdzenia")
                Spacer()
                if busy { ProgressView().controlSize(.small) }
            }.font(.callout).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Picker("Zakres", selection: $scope) {
                    Text("Bez folderu").tag(FavoriteScope.root)
                    Text("Wszystkie Ulubione").tag(FavoriteScope.all)
                    ForEach(folders) { folder in Text(folder.label).tag(folder.scope) }
                }.frame(maxWidth: 420).disabled(busy)
                Spacer(minLength: 4)
                Text("\(scopedPending.count) gotowych · \(pending.count) łącznie")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Ikona w cache nie musi być widoczna w Safari. Zaznacz strony z literami i wymuś naprawę.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Zaznacz widoczne") { marked.formUnion(shown.filter { $0.registered }.map { $0.host }) }.disabled(busy)
                Button("Odznacz") { marked.subtract(scoped.map { $0.host }) }.disabled(busy)
                Spacer(minLength: 4)
                Button("Napraw zaznaczone (\(markedSites.count))", action: prepareMarked).disabled(busy || markedSites.isEmpty)
            }
            HStack(spacing: 12) {
                Picker("", selection: $filter) {
                    ForEach(["Wszystkie", "Brakujące", "Gotowe"], id: \.self) { Text($0) }
                }.labelsHidden().pickerStyle(.segmented).frame(maxWidth: 320)
                Spacer(minLength: 4)
                TextField("Szukaj strony…", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder private func detail(_ s: Site) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(s.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
            Text(s.host).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Text(Array(Set(s.locations.map { $0.folderTitles.isEmpty ? "Bez folderu" : $0.folderTitles.joined(separator: " / ") })).sorted().joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(3)
            if s.locations.contains(where: { !scope.includes($0.folder) }) {
                Text("Wspólna ikona także poza tym zakresem.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                VStack(spacing: 4) { tile(s.existing, fallback: s.title, size: 68); Text("W cache").font(.caption) }
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                VStack(spacing: 4) { tile(pending[s.host]?.png ?? s.existing, fallback: s.title, size: 68); Text("Po zmianie").font(.caption) }
            }.frame(maxWidth: .infinity).padding(.vertical, 5)
            Text(s.status).font(.callout)
            Text(cacheDetails(s)).font(.caption).foregroundStyle(.secondary)
            Button("Wymuś naprawę tej ikony") { prepareSites([s]) }.disabled(busy || !s.registered)
            Button("Wybierz własną ikonę…") { choose(s) }.disabled(busy || !s.registered)
            if let p = pending[s.host] {
                Text(p.source).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Button("Odrzuć zmianę") { pending.removeValue(forKey: s.host); replacements.remove(s.host) }.disabled(busy)
            }
            if !s.registered {
                Text("Otwórz stronę w Safari i przeskanuj ponownie. Bez jednoznacznego rekordu nie zapisujemy.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            List(shown, selection: $selected) { s in siteRow(s).tag(s.host) }
                .frame(minWidth: 330, maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            ScrollView {
                if let s = site {
                    detail(s)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Wybierz stronę").font(.headline)
                        Text("Podgląd i własna grafika").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.trailing, 5)
            .frame(minWidth: 225, idealWidth: 270, maxWidth: 290, maxHeight: .infinity, alignment: .topLeading)
        }.frame(minHeight: 110, maxHeight: .infinity)
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Button("Przywróć kopię…", action: selectBackup).disabled(busy || permissionDenied)
                Button("Otwórz Safari") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                    }
                }
                Button("Ustawienia prywatności") {
                    if permissionDenied { showPermission = true } else { openPrivacySettings() }
                }
                Spacer()
            }
            Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                .lineLimit(2).help(message).frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true)
    }
    private var permissionSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wymagany dostęp do dysku").font(.title2.bold())
                    Text("Safari Icon Fixer nie może odczytać lub zmienić pamięci ikon Safari.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            Text("1. Otwórz Ustawienia systemowe → Prywatność i ochrona → Pełny dostęp do dysku.")
            Text("2. Włącz Safari Icon Fixer na liście. Jeśli go nie ma, kliknij + i wybierz aplikację z folderu Aplikacje.")
            Text("3. Wróć tutaj i sprawdź dostęp ponownie. Jeśli macOS poprosi o ponowne uruchomienie aplikacji, zaakceptuj.")
            Text("To szerokie uprawnienie systemowe. Aplikacja używa go do lokalnego dostępu do zakładek i cache ikon Safari; możesz je później cofnąć.")
                .font(.caption).foregroundStyle(.secondary)
            if !permissionHelp.isEmpty {
                Text(permissionHelp).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("Później") { waitingForPermission = false; showPermission = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Sprawdź ponownie", action: scan)
                Button("Otwórz ustawienia", action: openPrivacySettings)
                    .buttonStyle(.borderedProminent)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
        .frame(width: 520)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            controls.disabled(permissionDenied)
            content.layoutPriority(1).disabled(permissionDenied)
            Divider()
            footer
        }
        .padding(16)
        .frame(minWidth: 780, minHeight: 510)
        .onAppear(perform: scan)
        .sheet(isPresented: $showPermission, onDismiss: { waitingForPermission = false }) { permissionSheet }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if waitingForPermission && permissionDenied { runScan(presentPermission: false) }
            else if waitingForPermission { waitingForPermission = false }
        }
        .onChange(of: scope) { _ in selected = nil }
        .alert("Zastosować przygotowane ikony?",isPresented:$confirm) { Button("Anuluj",role:.cancel){}; Button("Zapisz",action:write) } message: { Text("Zakres: \(scopeLabel). Zapis: \(scopedPending.count) ikon. Safari współdzieli ikony domen, więc zmiana może być widoczna również w innych folderach i poza Ulubionymi. Zamknij Safari przez ⌘Q. Przed zapisem powstanie kopia cache.") }
        .alert("Przywrócić cały cache ikon?",isPresented:$confirmRestore) { Button("Anuluj",role:.cancel){}; Button("Przywróć",role:.destructive) { if let saved = chosenBackup { do { let displaced = try store.restore(saved); pending = [:]; replacements = []; marked = []; scan(); message = "Przywrócono kopię. Poprzedni cache: \(displaced.lastPathComponent)." } catch {handleOperationError(error)} } } } message: { Text("Wymaga zamknięcia Safari. Bieżący folder również zostanie zachowany jako kopia.") }
    }
}
@main struct SafariIconFixerApp: App { var body: some Scene { WindowGroup { MainView() }.defaultSize(width: 940, height: 640).windowResizability(.contentMinSize) } }
