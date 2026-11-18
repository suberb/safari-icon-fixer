import SwiftUI
import AppKit
import Combine
import Foundation

extension Notification.Name {
    static let sifAbout = Notification.Name("SafariIconFixer.showAbout")
    static let sifUpdate = Notification.Name("SafariIconFixer.checkUpdates")
}

enum AppReleaseInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.2" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "14" }
    static let repository = "suberb/safari-icon-fixer"
    static let repositoryURL = URL(string: "https://github.com/\(repository)")!
    static let releasesURL = repositoryURL.appendingPathComponent("releases")
    static let endpoint = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    #if arch(arm64)
    static let architecture = "arm64"
    #else
    static let architecture = "x86_64"
    #endif
    static func releaseURL(_ release: GitHubRelease) -> URL {
        guard let version = release.version else { return releasesURL }
        return releasesURL.appendingPathComponent("tag").appendingPathComponent(release.tagName.hasPrefix("v") ? "v\(version.string)" : version.string)
    }
    static func downloadURL(_ release: GitHubRelease) -> URL? {
        guard let version = release.version, let filename = release.macAsset(architecture: architecture) else { return nil }
        let tag = release.tagName.hasPrefix("v") ? "v\(version.string)" : version.string
        return releasesURL.appendingPathComponent("download").appendingPathComponent(tag).appendingPathComponent(filename)
    }
}

@MainActor final class AppUpdates: ObservableObject {
    @Published private(set) var available: GitHubRelease?
    @Published private(set) var checking = false
    @Published private(set) var status = "Nie sprawdzano aktualizacji."
    @Published var automatic: Bool = UserDefaults.standard.object(forKey: "sif.updates.auto") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automatic, forKey: "sif.updates.auto") }
    }
    private let lastAttemptKey = "sif.updates.lastAttempt"
    func checkIfDue() async {
        guard automatic, Date().timeIntervalSince1970 - UserDefaults.standard.double(forKey: lastAttemptKey) >= 86400 else { return }
        await check()
    }
    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        status = "Sprawdzanie w GitHub Releases…"
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastAttemptKey)
        do {
            var request = URLRequest(url: AppReleaseInfo.endpoint, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("SafariIconFixer/\(AppReleaseInfo.version)", forHTTPHeaderField: "User-Agent")
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false
            config.urlCache = nil
            let session = URLSession(configuration: config)
            defer { session.finishTasksAndInvalidate() }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { status = "Nieprawidłowa odpowiedź GitHub."; return }
            switch http.statusCode {
            case 200: break
            case 404: status = "Brak publicznego wydania lub repozytorium jest prywatne. Otwórz wydania w GitHub po zalogowaniu."; return
            case 403, 429: status = "GitHub ograniczył dostęp do API. Spróbuj później."; return
            default: status = "GitHub zwrócił błąd HTTP \(http.statusCode)."; return
            }
            guard let current = ReleaseVersion(AppReleaseInfo.version), let release = try? JSONDecoder().decode(GitHubRelease.self, from: data), let latest = release.version else {
                status = "Nie można odczytać numeru stabilnego wydania."; return
            }
            available = latest > current ? release : nil
            status = latest > current ? "Dostępna wersja \(latest.string)." : "Masz aktualną wersję."
        } catch {
            status = "Nie udało się połączyć z GitHub. Sprawdź internet i spróbuj ponownie."
        }
    }
}

@MainActor struct AppAboutView: View {
    @ObservedObject var updates: AppUpdates
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().scaledToFit().frame(width: 100, height: 100)
            VStack(spacing: 5) {
                Text("Safari Icon Fixer").font(.title.bold())
                Text("Wersja \(AppReleaseInfo.version) (\(AppReleaseInfo.build))").font(.subheadline).foregroundStyle(.secondary)
                Text("Ana × ChatGPT").font(.headline).foregroundStyle(Color.purple)
                Text("Twoje Safari. Twoje ikony.").font(.subheadline).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Aktualizacje").font(.headline)
                    Spacer()
                    if updates.checking { ProgressView().controlSize(.small) }
                    Button("Sprawdź teraz") { Task { await updates.check() } }.disabled(updates.checking)
                }
                Text(updates.status).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let release = updates.available {
                    if let notes = release.body, !notes.isEmpty {
                        ScrollView { Text(notes).font(.caption).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(maxHeight: 105)
                    }
                    HStack {
                        Link("Informacje o wydaniu", destination: AppReleaseInfo.releaseURL(release))
                        Spacer()
                        if let url = AppReleaseInfo.downloadURL(release) {
                            Button("Pobierz aktualizację") { NSWorkspace.shared.open(url) }.buttonStyle(.borderedProminent)
                        } else {
                            Link("Pobierz z GitHub", destination: AppReleaseInfo.releaseURL(release))
                        }
                    }
                }
                Toggle("Automatycznie sprawdzaj aktualizacje", isOn: $updates.automatic)
                Text("Sprawdzanie raz dziennie podczas uruchomienia lub powrotu do aplikacji. GitHub otrzymuje tylko zwykłe zapytanie o wydanie, nie zakładki ani ikony. Instalujesz aktualizację samodzielnie.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(14).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Link("GitHub", destination: AppReleaseInfo.repositoryURL)
                Link("Historia wersji i pobieranie", destination: AppReleaseInfo.releasesURL)
                Spacer()
                Button("Zamknij") { dismiss() }.keyboardShortcut(.defaultAction)
            }.font(.subheadline)
        }.padding(26).frame(width: 470)
    }
}
