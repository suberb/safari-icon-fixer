import Foundation

struct AppLanguage {
    struct Choice { let code: String; let name: String }
    static let choices = [Choice(code: "system", name: "Automatic (System)"), Choice(code: "en", name: "English"), Choice(code: "de", name: "Deutsch"), Choice(code: "fr", name: "Français"), Choice(code: "uk", name: "Українська"), Choice(code: "pl", name: "Polski"), Choice(code: "es", name: "Español")]
    static let supported = Set(choices.dropFirst().map(\.code))
    static let preferenceKey = "sif.language"
    static var selection: String { UserDefaults.standard.string(forKey: preferenceKey) ?? "system" }
    static func set(_ choice: String) { if choice == "system" || supported.contains(choice) { UserDefaults.standard.set(choice, forKey: preferenceKey) } }
    static func resolve(selection: String, preferred: [String]) -> String {
        if supported.contains(selection) { return selection }
        for language in preferred {
            let code = language.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init) ?? ""
            if supported.contains(code) { return code }
        }
        return "en"
    }
    // Freeze for a session: translated captions used by existing controls remain stable.
    // The user can choose another language for the next launch.
    static let active = resolve(selection: selection, preferred: Locale.preferredLanguages)
}

struct TranslationCatalog {
    let values: [String: [String: String]]
    init(data: Data) throws { values = try JSONDecoder().decode([String: [String: String]].self, from: data) }
    init(values: [String: [String: String]]) { self.values = values }
    func text(_ key: String, language: String, arguments: [String] = []) -> String {
        let template = values[language]?[key] ?? values["en"]?[key] ?? key
        // Substitute once, so braces in user-controlled titles/paths are never interpreted.
        guard let regex = try? NSRegularExpression(pattern: "\\{([0-9]+)\\}") else { return template }
        let ns = template as NSString
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: ns.length))
        var result = ""; var offset = 0
        for match in matches {
            result += ns.substring(with: NSRange(location: offset, length: match.range.location - offset))
            if let index = Int(ns.substring(with: match.range(at: 1))), arguments.indices.contains(index) { result += arguments[index] }
            else { result += ns.substring(with: match.range) }
            offset = NSMaxRange(match.range)
        }
        result += ns.substring(from: offset)
        return result
    }
    static let bundled: TranslationCatalog = {
        guard let url = Bundle.main.url(forResource: "Translations", withExtension: "json"), let data = try? Data(contentsOf: url), let catalog = try? TranslationCatalog(data: data) else { return TranslationCatalog(values: [:]) }
        return catalog
    }()
}

func l10n(_ key: String, _ args: String...) -> String { TranslationCatalog.bundled.text(key, language: AppLanguage.active, arguments: args) }
