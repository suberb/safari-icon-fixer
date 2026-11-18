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
