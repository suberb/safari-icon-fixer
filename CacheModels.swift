import Foundation
import CryptoKit

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
