import Foundation
let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jD1sAAAAASUVORK5CYII=")!
let a = IconCollection.Entry(host: "example.com", png: png, display: .fullTile)
let b = IconCollection.Entry(host: "www.example.org", png: png, display: nil)
let c = IconCollection(format: 1, icons: [a,b])
let roundTrip = try IconCollection.decode(c.encoded())
precondition(roundTrip == c)
precondition(c.matching(allowed: [a.host,b.host], alreadyPrepared: [a.host]) == [b])
precondition(c.matching(allowed: ["example.net"], alreadyPrepared: []) == [])
precondition(c.matching(allowed: [a.host], alreadyPrepared: []) == [a])
func reject(_ value: IconCollection) {
    do { _ = try value.encoded(); fatalError("invalid collection accepted") } catch {}
}
reject(.init(format: 2, icons: [a]))
reject(.init(format: 1, icons: [a,a]))
reject(.init(format: 1, icons: []))
for host in ["../example", "https://example.com", "EXAMPLE.COM", "a..com", "-a.com", "a.com/path", "a.com:8080"] {
    reject(.init(format: 1, icons: [.init(host: host, png: png, display: nil)]))
}
reject(.init(format: 1, icons: [.init(host: "example.com", png: Data([0,1,2]), display: nil)]))
var giant = png; giant[16] = 1
precondition(!IconCollection.validPNGHeader(giant))
precondition(IconCollection.validHost("xn--bcher-kva.example"))
func raster(_ color: IconRGB) -> IconRaster {
    let pixel = [UInt8(color.r),UInt8(color.g),UInt8(color.b),255]
    return IconRaster(width: 16, height: 16, rgba: Array(repeating: pixel, count: 256).flatMap { $0 })
}
let white = IconRGB(r:255,g:255,b:255), black = IconRGB(r:0,g:0,b:0), yellow = IconRGB(r:250,g:220,b:15), blue = IconRGB(r:20,g:75,b:180)
precondition(white.contrast(with: black) > 20.9)
for logo in [white,black,yellow,blue] {
    let bg = raster(logo).smartBackground()
    precondition(logo.contrast(with: bg) >= 3)
}
precondition(raster(white).smartBackground().luminance < 0.1)
precondition(raster(black).smartBackground().luminance > 0.6)
let empty = IconRaster(width: 4, height: 4, rgba: Array(repeating: 0, count: 64))
precondition(empty.smartBackground().luminance > 0.5)
print("OK: collection round trip, scope, protected drafts, bad hosts, malformed PNG headers, versions, and Smart Color contrast")
