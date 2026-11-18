import Foundation
func link(_ host: String, _ title: String) -> [String: Any] { ["URLString": "https://\(host)/", "URIDictionary": ["title": title]] }
func folder(_ title: String, _ children: [[String:Any]], uuid: String? = nil) -> [String:Any] { var result: [String:Any] = ["Title":title,"Children":children]; if let uuid = uuid { result["WebBookmarkUUID"] = uuid }; return result }
let data = folder("root", [folder("BookmarksBar", [link("google.com","Google"),link("youtube.com","YouTube"),folder("AI",[link("openai.com","ChatGPT"),link("google.com","Gemini"),folder("Tools",[link("tools.example","Tool")])],uuid:"ai"),folder("AI",[link("other.example","Other")]),folder("Empty",[])]),folder("BookmarksMenu",[link("outside.example","Outside")]),folder("ReadingList",[link("reading.example","Reading")])])
let serialized = try PropertyListSerialization.data(fromPropertyList:data,format:.binary,options:0)
let index = try FavoritesIndex(root: PropertyListSerialization.propertyList(from:serialized,format:nil) as! [String:Any])
precondition(index.hosts(in:.root) == ["google.com","youtube.com"])
precondition(index.hosts(in:.all) == ["google.com","youtube.com","openai.com","tools.example","other.example"])
let ai = index.folders.first { $0.path == ["uuid:ai"] }!
precondition(index.hosts(in:ai.scope) == ["google.com","openai.com","tools.example"])
let tools = index.folders.first {$0.label == "AI / Tools"}!
precondition(index.hosts(in:tools.scope) == ["tools.example"])
let other = index.folders.first {$0.label == "AI" && $0.id != ai.id}!
precondition(index.hosts(in:other.scope) == ["other.example"])
precondition(index.hosts(in:index.folders.first {$0.label == "Empty"}!.scope).isEmpty)
precondition(index.links.filter {$0.host == "google.com"}.count == 2)
precondition(Set(index.links.filter {$0.host == "google.com" && FavoriteScope.root.includes($0.folder)}.map(\.title)) == ["Google"])
precondition(Set(index.links.filter {$0.host == "google.com" && ai.scope.includes($0.folder)}.map(\.title)) == ["Gemini"])
let prepared = ["google.com":1,"openai.com":2,"outside.example":3,"youtube.com":4]
let rootBatch = prepared.filter {index.hosts(in:.root).contains($0.key)}
let folderBatch = prepared.filter {index.hosts(in:ai.scope).contains($0.key)}
precondition(Set(rootBatch.keys) == ["google.com","youtube.com"])
precondition(Set(folderBatch.keys) == ["google.com","openai.com"])
do { _ = try FavoritesIndex(root:folder("root",[folder("BookmarksMenu",[])])); fatalError("missing favorites must fail") } catch FavoritesIndex.ReadError.unknownFavorites {}
print("OK: root / all / nested folders / duplicate names / shared hosts / empty folder / scoped batches / missing favorites")

// Permission denial is distinct from absent files and schema errors.
precondition(isSafariPermissionError(NSError(domain: NSCocoaErrorDomain, code: 257)))
precondition(isSafariPermissionError(NSError(domain: NSCocoaErrorDomain, code: 513)))
precondition(isSafariPermissionError(NSError(domain: NSPOSIXErrorDomain, code: 1)))
precondition(isSafariPermissionError(NSError(domain: NSPOSIXErrorDomain, code: 13)))
precondition(isSafariPermissionError(NSError(domain: "Wrapped", code: 0, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 13)])))
precondition(isSafariPermissionError(NSError(domain: "SQLite", code: 0, userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])))
precondition(!isSafariPermissionError(NSError(domain: NSCocoaErrorDomain, code: 260)))
precondition(!isSafariPermissionError(NSError(domain: NSPOSIXErrorDomain, code: 2)))
precondition(!isSafariPermissionError(NSError(domain: "Schema", code: 0, userInfo: [NSLocalizedDescriptionKey: "Nieznany schemat cache Safari."])))
print("OK: permission denial / wrapped error / missing files / schema error")
