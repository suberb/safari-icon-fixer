import SwiftUI
import AppKit

@MainActor struct BackupManagerView: View {
    let root: URL
    let safariOpen: Bool
    let onRestore: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [BackupEntry] = []
    @State private var selected: String?
    @State private var loading = true
    @State private var failure: String?
    @State private var confirmTrash = false
    @State private var trashID: String?
    private var chosen: BackupEntry? { entries.first { $0.id == selected } }
    private var canTrash: Bool { chosen != nil && selected != entries.first?.id && entries.count > 1 && !loading && failure == nil }
    private func format(_ bytes: Int64?) -> String { bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? l10n("Nieznany") }
    private func refresh() async {
        loading = true; failure = nil
        let path = root
        let worker = Task.detached(priority: .utility) { try BackupInventory.list(path) }
        defer { loading = false }
        do {
            entries = try await worker.value
            if !entries.contains(where: { $0.id == selected }) { selected = entries.first?.id }
        } catch {
            entries = []; selected = nil; failure = error.localizedDescription
        }
    }
    private func moveToTrash() {
        guard let id = trashID else { return }
        trashID = nil
        do {
            let url = try BackupInventory.removable(root, id: id)
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            Task { await refresh() }
        } catch { failure = error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n("Kopie zapasowe")).font(.title2.bold())
                    Text(l10n("Lokalne kopie ikon i ustawień. Najnowsza kopia jest chroniona.")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }.disabled(loading).help(l10n("Odśwież kopie"))
            }
            if loading { ProgressView().frame(maxWidth: .infinity, minHeight: 260) }
            else if entries.isEmpty {
                Text(failure ?? l10n("Nie ma jeszcze kopii zapasowych.")).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 260)
            } else {
                List(selection: $selected) {
                    ForEach(entries) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath").font(.title3).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.date, style: .date).font(.callout.weight(.medium))
                                Text(entry.date, style: .time).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entry.id == entries.first?.id { Text(l10n("Najnowsza")).font(.caption).foregroundStyle(.secondary) }
                            Text(format(entry.bytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }.padding(.vertical, 5).tag(entry.id)
                    }
                }.frame(minHeight: 260, maxHeight: 350)
                if entries.allSatisfy({ $0.bytes != nil }) {
                    let total = entries.reduce(Int64(0)) { sum, entry in
                        let result = sum.addingReportingOverflow(entry.bytes ?? 0)
                        return result.overflow ? Int64.max : result.partialValue
                    }
                    Text(l10n("Łączny rozmiar plików: {0}", format(total))).font(.caption).foregroundStyle(.secondary)
                }
                if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
            }
            if safariOpen { Label(l10n("Przejdź do Safari i naciśnij ⌘Q, aby zastosować zmiany."), systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button(l10n("Pokaż w Finderze")) { NSWorkspace.shared.activateFileViewerSelecting([root]) }.disabled(entries.isEmpty || loading)
                Button(l10n("Przenieś do Kosza"), role: .destructive) { trashID = selected; confirmTrash = true }.disabled(!canTrash)
                Spacer()
                Button(l10n("Zamknij")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(l10n("Przywróć")) { if let chosen { onRestore(chosen.url) } }.buttonStyle(.borderedProminent).disabled(chosen == nil || loading || safariOpen || failure != nil)
            }
        }.padding(22).frame(minWidth: 560, idealWidth: 620)
        .task { await refresh() }
        .alert(l10n("Przenieść kopię do Kosza?"), isPresented: $confirmTrash) {
            Button(l10n("Anuluj"), role: .cancel) { trashID = nil }
            Button(l10n("Przenieś do Kosza"), role: .destructive, action: moveToTrash)
        } message: { Text(l10n("Usuniesz tylko wybraną kopię. Bieżące ikony Safari i chronione grafiki pozostaną bez zmian.")) }
    }
}
