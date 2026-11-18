import Foundation
let data = try Data(contentsOf: URL(fileURLWithPath: "Resources/Translations.json"))
let catalog = try TranslationCatalog(data: data)
let keys = Set(catalog.values["pl"]!.keys)
precondition(keys.count > 220)
for language in AppLanguage.supported {
    precondition(Set(catalog.values[language]!.keys) == keys)
    precondition(catalog.values[language]!.values.allSatisfy { !$0.isEmpty })
}
precondition(AppLanguage.resolve(selection: "system", preferred: ["de-DE"]) == "de")
precondition(AppLanguage.resolve(selection: "system", preferred: ["ja-JP", "uk-UA"]) == "uk")
precondition(AppLanguage.resolve(selection: "system", preferred: ["ja-JP"]) == "en")
precondition(AppLanguage.resolve(selection: "fr", preferred: ["pl-PL"]) == "fr")
precondition(catalog.text("Zastosuj ({0})", language: "en", arguments: ["4"]) == "Apply (4)")
precondition(catalog.text("Zapis przerwany: {0}. Kopia: {1}", language: "en", arguments: ["{1}", "Backup"]) == "Writing interrupted: {1}. Backup: Backup")
precondition(catalog.text("Bez folderu", language: "es") == "Sin carpeta")
print("OK: \(keys.count) keys × \(AppLanguage.supported.count) languages; locale resolution and placeholder safety")
