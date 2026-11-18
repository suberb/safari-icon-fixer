import SwiftUI
import AppKit
import Combine
import Foundation
import Sparkle

extension Notification.Name {
    static let sifAbout = Notification.Name("SafariIconFixer.showAbout")
    static let sifUpdate = Notification.Name("SafariIconFixer.checkUpdates")
}

enum AppReleaseInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.7.1" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "28" }
    static let repository = "suberb/safari-icon-fixer"
    static let repositoryURL = URL(string: "https://github.com/\(repository)")!
    static let releasesURL = repositoryURL.appendingPathComponent("releases")
}

@MainActor final class AppUpdates: ObservableObject {
    static let shared = AppUpdates()
    private let controller: SPUStandardUpdaterController
    private var started = false
    @Published private(set) var automatic = false
    @Published private(set) var autoInstall = false
    @Published private(set) var canCheck = false
    @Published private(set) var canAutoInstall = false

    private init() {
        // Migrate the old app preference once, before Sparkle reads its defaults.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "SUEnableAutomaticChecks") == nil,
           let previous = defaults.object(forKey: "sif.updates.auto") as? Bool {
            defaults.set(previous, forKey: "SUEnableAutomaticChecks")
        }
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automatic)
        updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$autoInstall)
        updater.publisher(for: \.allowsAutomaticUpdates).assign(to: &$canAutoInstall)
    }
    func checkAtLaunch() {
        guard !started else { return }
        started = true
        controller.startUpdater()
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
    }
    func check() {
        if !started { checkAtLaunch() }
        guard controller.updater.canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }
    func setAutomatic(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
        if !enabled { controller.updater.automaticallyDownloadsUpdates = false }
    }
    func setAutoInstall(_ enabled: Bool) {
        guard controller.updater.allowsAutomaticUpdates else { return }
        controller.updater.automaticallyDownloadsUpdates = enabled
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
                Text(l10n("Wersja {0} ({1})", String(describing: AppReleaseInfo.version), String(describing: AppReleaseInfo.build))).font(.subheadline).foregroundStyle(.secondary)
                Text("hempbiscuit & the machine").font(.headline).foregroundStyle(Color.purple)
                Text(l10n("Twoje Safari. Twoje ikony.")).font(.subheadline).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(l10n("Aktualizacje")).font(.headline)
                    Spacer()
                    Button(l10n("Sprawdź teraz")) { updates.check() }.disabled(!updates.canCheck)
                }
                Toggle(l10n("Automatycznie sprawdzaj aktualizacje"), isOn: Binding(get: { updates.automatic }, set: { updates.setAutomatic($0) }))
                Toggle(l10n("Automatycznie pobieraj i instaluj aktualizacje"), isOn: Binding(get: { updates.autoInstall }, set: { updates.setAutoInstall($0) })).disabled(!updates.canAutoInstall)
                Text(l10n("Sparkle sprawdza podpis aktualizacji. Przy włączonej automatycznej instalacji aktualizacja może zostać zainstalowana przy zamknięciu aplikacji. Przed aktualizacją zapisz przygotowane ikony."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(14).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Link("GitHub", destination: AppReleaseInfo.repositoryURL)
                Link(l10n("Historia wersji i pobieranie"), destination: AppReleaseInfo.releasesURL)
                Spacer()
                Button(l10n("Zamknij")) { dismiss() }.keyboardShortcut(.defaultAction)
            }.font(.subheadline)
        }.padding(26).frame(width: 470)
    }
}
