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

let queryText = "Google Drive logo & icon"
let searchURL = commonsSearchURL(queryText)!
let components = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)!
precondition(components.queryItems?.first(where: { $0.name == "gsrsearch" })?.value == queryText)
precondition(allowedCommonsURL(searchURL))
precondition(allowedCommonsURL(URL(string:"https://upload.wikimedia.org/wikipedia/commons/a/a1/logo.png")!))
precondition(!allowedCommonsURL(URL(string:"https://commons.wikimedia.org.example.com/evil")!))
precondition(!allowedCommonsURL(URL(string:"http://commons.wikimedia.org/")!))
precondition(!allowedCommonsURL(URL(string:"https://commons.wikimedia.org:8443/")!))
let fixture = Data(#"{"query":{"pages":[{"title":"File:Logo.svg","index":1,"imageinfo":[{"url":"https://upload.wikimedia.org/a.svg","thumburl":"https://upload.wikimedia.org/a.png","descriptionurl":"https://commons.wikimedia.org/wiki/File:Logo.svg","mime":"image/svg+xml"}]}]}}"#.utf8)
let page = try JSONDecoder().decode(CommonsResponse.self, from: fixture).query?.pages?.first
precondition(page?.title == "File:Logo.svg" && page?.imageinfo?.first?.thumburl?.path == "/a.png")
print("OK: Commons search URL / encoding / allowlist / JSON fixture")

let google = googleImageSearchURL(queryText, transparent: true)!
let googleItems = URLComponents(url:google,resolvingAgainstBaseURL:false)!.queryItems!
precondition(googleItems.contains(URLQueryItem(name:"q",value:queryText)))
precondition(googleItems.contains(URLQueryItem(name:"tbs",value:"ic:trans")))
precondition(googlePageURL(google) && googlePageURL(URL(string:"https://consent.google.com/")!))
precondition(!googlePageURL(URL(string:"https://google.com.example.net/")!))
precondition(publicImageURL(URL(string:"https://encrypted-tbn0.gstatic.com/image")!))
for bad in ["file:///etc/passwd","http://example.com/image","https://127.0.0.1/x","https://localhost/x","https://router.local/x","https://[::1]/x","https://example.com:8443/x","https://user@example.com/x"] { precondition(!publicImageURL(URL(string:bad)!)) }
print("OK: Google query / transparency filter / origin and URL checks")

func tile(_ size: Int, pad: Int, fill: IconRGB, logo: IconRGB) -> IconRaster {
    var bytes = [UInt8](repeating: 0, count: size*size*4)
    for y in pad..<(size-pad) { for x in pad..<(size-pad) {
        let center = x >= size/3 && x < size*2/3 && y >= size/3 && y < size*2/3
        let c = center ? logo : fill; let i = (y*size+x)*4
        bytes[i] = UInt8(c.r); bytes[i+1] = UInt8(c.g); bytes[i+2] = UInt8(c.b); bytes[i+3] = 255
    } }
    return IconRaster(width:size,height:size,rgba:bytes)
}
let white = IconRGB(r:255,g:255,b:255), blue = IconRGB(r:20,g:90,b:220)
for padding in [0,4] {
    let image = tile(36,pad:padding,fill:white,logo:blue)
    precondition(image.edgeBackground() == white)
    let clean = image.removingEdgeBackground(white)!
    precondition(clean.bounds() == IconBounds(x:12,y:12,width:12,height:12))
    precondition(clean.alpha(0) == 0 && clean.rgb(18*36+18) == blue)
    precondition(clean.dominantColor() == blue)
}
precondition(blue.lightened(0.30) == IconRGB(r:91,g:140,b:231))
precondition(blue.lightened(0.40) == IconRGB(r:114,g:156,b:234))
precondition(blue.lightened(0.50) == IconRGB(r:138,g:173,b:238))
var solid = tile(36,pad:0,fill:blue,logo:blue)
precondition(solid.removingEdgeBackground(blue) == nil)
var ring = tile(36,pad:4,fill:white,logo:blue)
for y in 15..<20 { for x in 15..<20 { let i = (y*36+x)*4; ring.rgba[i] = 255; ring.rgba[i+1] = 255; ring.rgba[i+2] = 255 } }
let preserved = ring.removingEdgeBackground(white)!
precondition(preserved.alpha(17*36+17) == 255 && preserved.rgb(17*36+17) == white)
print("OK: padded/opaque backgrounds, connected removal, enclosed white detail, dominant color, 30–50% lightening")
precondition(isGoogleImageHost("encrypted-tbn0.gstatic.com"))
precondition(isGoogleImageHost("lh3.googleusercontent.com"))
precondition(!isGoogleImageHost("gstatic.com.example.net"))
precondition(!isGoogleImageHost(nil))
print("OK: Google CDN redirect boundaries")
precondition(iconDisplayAssignment(nil) == "")
precondition(iconDisplayAssignment(.fullTile) == ", transparency_analysis_result=1")
precondition(iconDisplayAssignment(.systemTile) == ", transparency_analysis_result=0")
print("OK: full tile / system tile / unchanged style SQL assignment")
let selectionOrder = ["a", "b", "c", "d"]
let first = LibrarySelection.click("b", ordered: selectionOrder, selected: [], anchor: nil, extend: false, toggle: false)
precondition(first.selected == ["b"] && first.anchor == "b")
let range = LibrarySelection.click("d", ordered: selectionOrder, selected: first.selected, anchor: first.anchor, extend: true, toggle: false)
precondition(range.selected == ["b", "c", "d"])
let toggle = LibrarySelection.click("c", ordered: selectionOrder, selected: range.selected.union(["hidden"]), anchor: range.anchor, extend: false, toggle: true)
precondition(toggle.selected == ["b", "d"])
precondition(LibrarySelection.click("a", ordered: selectionOrder, selected: toggle.selected, anchor: "d", extend: true, toggle: false).selected == Set(selectionOrder))
print("OK: visible-order selection / Command / Shift")
