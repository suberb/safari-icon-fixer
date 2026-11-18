import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct IconCandidate: Identifiable {
    let id = UUID()
    let title: String
    let png: Data
    let pixels: Int
    let source: String
    let page: URL?
    var transparent: Bool { hasTransparentPixels(png) }
}

private final class CommonsPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(allowedCommonsURL) == true ? request : nil)
    }
}

func searchCommons(_ text: String) async throws -> [IconCandidate] {
    guard let url = commonsSearchURL(text) else { throw fail("Nieprawidłowe wyszukiwanie.") }
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 10
    config.timeoutIntervalForResource = 20
    config.httpShouldSetCookies = false
    config.urlCredentialStorage = nil
    config.httpAdditionalHeaders = ["User-Agent": "SafariIconFixer/0.2.9 (personal macOS icon utility)"]
    let session = URLSession(configuration: config, delegate: CommonsPolicy(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    func get(_ url: URL, limit: Int) async throws -> Data {
        guard allowedCommonsURL(url) else { throw fail("Nieobsługiwane źródło obrazu.") }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, let final = http.url, allowedCommonsURL(final), (200..<300).contains(http.statusCode), http.expectedContentLength <= Int64(limit) else { throw fail("Serwer nie zwrócił prawidłowego wyniku.") }
        var data = Data()
        for try await byte in bytes {
            if data.count >= limit { throw fail("Plik przekracza limit pobierania.") }
            data.append(byte)
        }
        return data
    }
    let json = try await get(url, limit: 2_000_000)
    let decoded = try JSONDecoder().decode(CommonsResponse.self, from: json)
    let pages = (decoded.query?.pages ?? []).sorted { ($0.index ?? Int.max) < ($1.index ?? Int.max) }
    var results: [IconCandidate] = []
    for page in pages {
        try Task.checkCancellation()
        guard let info = page.imageinfo?.first, info.mime?.hasPrefix("image/") == true, let imageURL = info.thumburl ?? info.url, allowedCommonsURL(imageURL) else { continue }
        do {
            let data = try await get(imageURL, limit: 8_000_000)
            if let (png, size) = safePNG(data), !results.contains(where: { $0.png == png }) {
                let sourcePage = info.descriptionurl.flatMap { allowedCommonsURL($0) ? $0 : nil }
                results.append(IconCandidate(title: page.title.replacingOccurrences(of: "File:", with: ""), png: png, pixels: size, source: sourcePage?.absoluteString ?? imageURL.absoluteString, page: sourcePage))
            }
        } catch { try Task.checkCancellation(); continue }
        if results.count >= 16 { break }
    }
    return results
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 10
            for row in 0..<Int(ceil(size.height / step)) {
                for col in 0..<Int(ceil(size.width / step)) {
                    let rect = CGRect(x: CGFloat(col)*step, y: CGFloat(row)*step, width: step, height: step)
                    context.fill(Path(rect), with: .color((row + col).isMultiple(of: 2) ? .white : Color(white: 0.8)))
                }
            }
        }
    }
}

@MainActor struct IconSearchView: View {
    let host: String
    let title: String
    let existing: Data?
    let onChoose: (Pending) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [IconCandidate] = []
    @State private var selected: IconCandidate?
    @State private var background: IconBackground = .original
    @State private var color: Color = .white
    @State private var inset = 0.12
    @State private var lightening = 0.40
    @State private var art: IconArtwork?
    @State private var googleURL: URL?
    @State private var showingGoogle = true
    @State private var googleFilter = "Wszystkie"
    @State private var picking = false
    @State private var filter = "Wszystkie"
    @State private var status = "Wybierz źródło lub zmień tło istniejącej ikony."
    @State private var loading = false
    @State private var job: Task<Void, Never>?
    @State private var generation = UUID()

    private var visible: [IconCandidate] {
        results.filter { item in filter == "Wszystkie" || (filter == "Przezroczyste" ? item.transparent : !item.transparent) }
    }
    private var preview: Data? {
        guard let art else { return nil }
        return composeArtwork(art, background: background, color: NSColor(color), inset: inset, lightening: lightening)
    }
    private func start(website: Bool) {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard website || !term.isEmpty else { return }
        job?.cancel()
        let token = UUID(); generation = token
        showingGoogle = false; picking = false
        loading = true; status = website ? "Pobieranie ikon ze strony…" : "Wyszukiwanie w Wikimedia Commons…"
        job = Task {
            do {
                let found: [IconCandidate]
                if website { found = await fetchWebsiteIcons(host, multiple: true) }
                else { found = try await searchCommons(term) }
                guard !Task.isCancelled, generation == token else { return }
                for item in found where !results.contains(where: { $0.png == item.png }) { results.append(item) }
                if selected == nil, let first = found.first { select(first) }
                status = found.isEmpty ? "Brak wyników. Zmień zapytanie lub wybierz plik." : "Pobrane wyniki: \(found.count). Wybierz grafikę."
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                status = "Błąd wyszukiwania: \(error.localizedDescription)"
            }
            loading = false
        }
    }
    private func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 8_000_000, let (png, pixels) = safePNG(try Data(contentsOf: url)) else { throw fail("Nieobsługiwany obraz lub plik większy niż 8 MB.") }
            let item = IconCandidate(title: url.lastPathComponent, png: png, pixels: pixels, source: url.lastPathComponent, page: nil)
            results.append(item); select(item); filter = "Wszystkie"; status = "Dodano plik lokalny."
        } catch { status = error.localizedDescription }
    }
    private func select(_ item: IconCandidate) {
        selected = item; art = IconArtwork(item.png)
        if art?.separate == false { background = .original }
    }
    private func runGoogle() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = googleImageSearchURL(text, transparent: googleFilter == "Przezroczyste") else { return }
        job?.cancel(); generation = UUID(); loading = false
        showingGoogle = true; picking = false; googleURL = url
        status = "Otwórz podgląd wyniku, następnie kliknij Wybierz obraz i sam obraz."
    }
    private func browserSearch() { if let url = googleImageSearchURL(query, transparent: googleFilter == "Przezroczyste") { NSWorkspace.shared.open(url) } }
    private func addImage(_ data: Data, source: String) throws {
        guard let (png, size) = safePNG(data) else { throw fail("Nie udało się odczytać obrazu. Spróbuj wybrać inny.") }
        let item = IconCandidate(title: "\(title) · \(size) px", png: png, pixels: size, source: source, page: nil)
        results.append(item); select(item); filter = "Wszystkie"
        status = size < 128 ? "Mały obraz (\(size) px). Wybierz większy podgląd dla lepszej jakości." : "Obraz pobrany (\(size) px). Ustaw tło i margines."
    }
    private func takeGoogleImage(_ value: String) {
        picking = false; job?.cancel(); generation = UUID(); loading = false
        guard !value.isEmpty else { status = "Nie wykryto obrazu w tym miejscu. Kliknij środek powiększonego podglądu lub skopiuj obraz/adres i wklej tutaj."; return }
        let token = UUID(); generation = token; loading = true; status = "Pobieram wybraną grafikę…"
        job = Task {
            do {
                let (data, source) = try await selectedGoogleImage(value)
                guard !Task.isCancelled, generation == token else { return }
                try addImage(data, source: source)
                showingGoogle = false
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                status = "\(error.localizedDescription) Skopiuj obraz lub jego adres prawym przyciskiem i wybierz Wklej obraz/adres."
            }
            loading = false
        }
    }
    private func pasteImage() {
        picking = false; job?.cancel(); generation = UUID(); loading = false
        let paste = NSPasteboard.general
        do {
            if let data = paste.data(forType: .png) ?? paste.data(forType: .tiff) { try addImage(data, source: "Schowek"); showingGoogle = false; return }
            if let images = paste.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], let data = images.first?.tiffRepresentation { try addImage(data, source: "Schowek"); showingGoogle = false; return }
            let value = (paste.string(forType: .URL) ?? paste.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("data:image/") || URL(string: value).map(publicImageURL) == true { takeGoogleImage(value); return }
            status = "W schowku nie ma obrazu ani adresu HTTPS. Użyj Kopiuj obraz / Kopiuj adres obrazu."
        } catch { status = error.localizedDescription }
    }
    private func imageTile(_ data: Data, size: CGFloat) -> some View {
        ZStack {
            Checkerboard()
            if let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit() }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 8))
    }
    private func resultCell(_ item: IconCandidate) -> some View {
        Button {
            select(item)
        } label: {
            VStack(spacing: 5) {
                imageTile(item.png, size: 62)
                Text(item.title).font(.caption).lineLimit(1)
                Text(item.transparent ? "Z alfa" : "Pełne tło").font(.caption2).foregroundStyle(.secondary)
            }.padding(6).frame(maxWidth: .infinity)
                .background(selected?.id == item.id ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected?.id == item.id ? Color.accentColor : Color.secondary.opacity(0.2)))
        }.buttonStyle(.plain).help(item.title)
    }
    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Nazwa, np. Google Drive logo", text: $query).textFieldStyle(.roundedBorder).onSubmit { runGoogle() }
                Picker("", selection: $googleFilter) { Text("Wszystkie").tag("Wszystkie"); Text("Przezroczyste").tag("Przezroczyste") }.labelsHidden().frame(width: 135)
                Button("Szukaj w Google") { runGoogle() }.buttonStyle(.borderedProminent).disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack {
                Button("Ikony ze strony") { start(website: true) }
                Button("Commons") { start(website: false) }
                Button("Dodaj plik…", action: importFile)
                Button("Wklej obraz/adres", action: pasteImage)
                Spacer()
                if loading { ProgressView().controlSize(.small); Button("Stop") { job?.cancel(); generation = UUID(); loading = false; status = "Przerwano." } }
            }
            Text("Google otrzymuje wpisane zapytanie, bez listy zakładek. Wyniki otwierają się w osadzonej przeglądarce.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Źródło", selection: $showingGoogle) {
                Text("Google Grafika").tag(true)
                Text("Zebrane ikony (\(results.count))").tag(false)
            }.pickerStyle(.segmented).labelsHidden()
            if showingGoogle {
                HStack {
                    Button(picking ? "Anuluj wybór" : "Wybierz obraz") { picking.toggle() }.buttonStyle(.borderedProminent).disabled(googleURL == nil || loading)
                    Spacer()
                    Button("Otwórz w przeglądarce", action: browserSearch).font(.caption)
                }
                if googleURL == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Wpisz frazę i kliknij Szukaj w Google.").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GoogleImageBrowser(url: googleURL, picking: picking, onImage: takeGoogleImage, onNotice: { status = $0 })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(picking ? "Kliknij środek obrazu w wynikach lub podglądzie." : "Kliknij zwykły wynik, by go powiększyć. Potem wybierz obraz (lub ⌥ + klik). Możesz też skopiować obraz lub adres prawym przyciskiem i wkleić go powyżej.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("", selection: $filter) { ForEach(["Wszystkie", "Przezroczyste", "Z tłem"], id: \.self) { Text($0).tag($0) } }.labelsHidden().pickerStyle(.segmented)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) { ForEach(visible) { resultCell($0) } }.padding(2)
                    if visible.isEmpty { Text("Brak ikon w tym widoku.").foregroundStyle(.secondary).padding(12) }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var automaticColor: Color {
        let base = art?.dominant ?? IconRGB(r: 128, g: 128, b: 128)
        return Color(nsColor: nsColor(base.lightened(lightening)))
    }
    private var editPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Podgląd po zmianie").font(.headline)
            if let data = preview {
                HStack {
                    Spacer()
                    ZStack {
                        RoundedRectangle(cornerRadius: 23, style: .continuous).fill(Color(white: 0.48))
                        if let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit() }
                    }.frame(width: 112, height: 112).clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                    Spacer()
                }
                Text(selected?.title ?? "").font(.caption).lineLimit(2)
                Picker("Tło", selection: $background) { ForEach(IconBackground.allCases) { Text($0.rawValue).tag($0) } }.disabled(art?.separate != true)
                if background == .custom { ColorPicker("Kolor tła", selection: $color, supportsOpacity: false) }
                if background == .automatic {
                    HStack {
                        RoundedRectangle(cornerRadius: 5).fill(automaticColor).frame(width: 32, height: 24)
                        Text("Rozjaśnienie: \(Int((lightening*100).rounded()))%") .font(.caption)
                    }
                    Slider(value: $lightening, in: 0.30...0.50, step: 0.01)
                }
                HStack { Text("Margines logo"); Slider(value: $inset, in: 0...0.30); Text("\(Int((inset*100).rounded()))%") .monospacedDigit().font(.caption) }.disabled(art?.separate != true)
                if art?.separate == false {
                    Text("Tło tej grafiki jest złożone. Zachowuję cały obraz, żeby nie tworzyć kwadratu z ostrymi rogami. Wybierz logo z jednolitym lub przezroczystym tłem.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Margines zmienia tylko logo. Pełne tło zawsze wypełnia kafelek.").font(.caption).foregroundStyle(.secondary)
                }
                if let page = selected?.page { Link("Źródło i licencja", destination: page).font(.caption) }
            } else {
                Text("Wybierz wynik z listy.").foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.frame(width: 235, alignment: .topLeading)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Znajdź ikonę — \(title)").font(.title2.bold()).lineLimit(1)
            Text(host).font(.caption).foregroundStyle(.secondary)
            searchControls
            Divider()
            HStack(alignment: .top, spacing: 12) {
                sourcePanel
                Divider()
                ScrollView { editPanel }
            }.frame(minHeight: 300, maxHeight: .infinity)
            Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Divider()
            HStack {
                Button("Anuluj") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Użyj tej ikony") {
                    if let data = preview, let selected { onChoose(Pending(png: data, source: selected.source + " · tło: " + background.rawValue, custom: true)); dismiss() }
                }.buttonStyle(.borderedProminent).disabled(preview == nil || loading || picking)
            }
        }.padding(18).frame(minWidth: 720, idealWidth: 900, minHeight: 505, idealHeight: 620)
        .onAppear {
            query = title + " logo"
            if let existing, let (png, pixels) = safePNG(existing) {
                let item = IconCandidate(title: "Obecna / przygotowana ikona", png: png, pixels: pixels, source: "Lokalna ikona", page: nil)
                results = [item]; select(item)
            }
        }
        .onDisappear { job?.cancel(); generation = UUID() }
    }
}
