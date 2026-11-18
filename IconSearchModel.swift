import Foundation

struct CommonsResponse: Decodable {
    struct Query: Decodable { let pages: [Page]? }
    struct Page: Decodable {
        let title: String
        let index: Int?
        let imageinfo: [Info]?
    }
    struct Info: Decodable {
        let url: URL?
        let thumburl: URL?
        let descriptionurl: URL?
        let mime: String?
    }
    let query: Query?
}

func commonsSearchURL(_ text: String) -> URL? {
    var parts = URLComponents(string: "https://commons.wikimedia.org/w/api.php")
    parts?.queryItems = [
        URLQueryItem(name: "action", value: "query"),
        URLQueryItem(name: "generator", value: "search"),
        URLQueryItem(name: "gsrsearch", value: text),
        URLQueryItem(name: "gsrnamespace", value: "6"),
        URLQueryItem(name: "gsrlimit", value: "24"),
        URLQueryItem(name: "prop", value: "imageinfo"),
        URLQueryItem(name: "iiprop", value: "url|mime"),
        URLQueryItem(name: "iiurlwidth", value: "512"),
        URLQueryItem(name: "format", value: "json"),
        URLQueryItem(name: "formatversion", value: "2")
    ]
    return parts?.url
}

func allowedCommonsURL(_ url: URL) -> Bool {
    guard url.scheme == "https", url.user == nil, url.password == nil,
          url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
    return host == "commons.wikimedia.org" || host == "upload.wikimedia.org"
}

func googleImageSearchURL(_ text: String, transparent: Bool = false) -> URL? {
    var components = URLComponents(string: "https://www.google.com/search")
    components?.queryItems = [URLQueryItem(name: "tbm", value: "isch"), URLQueryItem(name: "q", value: text)]
    if transparent { components?.queryItems?.append(URLQueryItem(name: "tbs", value: "ic:trans")) }
    return components?.url
}
func googlePageURL(_ url: URL) -> Bool {
    guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
    return host == "google.com" || host.hasSuffix(".google.com") || host == "google.pl" || host.hasSuffix(".google.pl")
}
// Only explicit user-selected HTTPS images. Reject literal addresses and local names.
func publicImageURL(_ url: URL) -> Bool {
    guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443, let host = url.host?.lowercased(), host.contains("."), !host.hasSuffix("."), !host.contains(":"), !host.hasSuffix(".local"), !host.hasSuffix(".internal"), !host.hasSuffix(".localhost"), !host.hasSuffix(".lan"), !host.hasSuffix(".home"), !host.hasSuffix(".test"), !host.hasSuffix(".invalid"), !host.hasSuffix(".example") else { return false }
    guard let tld = host.split(separator: ".").last, tld.first?.isLetter == true, tld.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return false }
    return true
}

func isGoogleImageHost(_ host: String?) -> Bool {
    guard let host = host?.lowercased() else { return false }
    return ["gstatic.com", "googleusercontent.com", "google.com"].contains { host == $0 || host.hasSuffix("." + $0) }
}
