import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

private func decodedIcon(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func hasTransparentPixels(_ data: Data) -> Bool {
    guard let image = decodedIcon(data) else { return false }
    let side = 64
    var buffer = [UInt8](repeating: 0, count: side * side * 4)
    return buffer.withUnsafeMutableBytes { bytes -> Bool in
        guard let ctx = CGContext(data: bytes.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        for i in stride(from: 3, to: bytes.count, by: 4) { if bytes[i] < 240 { return true } }
        return false
    }
}

enum IconBackground: String, CaseIterable, Identifiable {
    case original = "Oryginalne", transparent = "Przezroczyste", white = "Białe", automatic = "Kolor z ikony", smart = "Inteligentne tło", custom = "Własny kolor"
    var id: String { rawValue }
}
private let iconBitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
private func raster(_ image: CGImage) -> IconRaster? {
    let side = 256
    var bytes = [UInt8](repeating: 0, count: side*side*4)
    let valid = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: iconBitmapInfo) else { return false }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return true
    }
    return valid ? IconRaster(width: side, height: side, rgba: bytes) : nil
}
func nsColor(_ rgb: IconRGB) -> NSColor {
    NSColor(red: CGFloat(rgb.r)/255, green: CGFloat(rgb.g)/255, blue: CGFloat(rgb.b)/255, alpha: 1)
}
struct IconArtwork {
    let original: CGImage
    let foreground: CGImage
    let bounds: IconBounds
    let backdrop: IconRGB?
    let dominant: IconRGB?
    let smartColor: IconRGB
    let separate: Bool
    init?(_ png: Data) {
        guard let image = decodedIcon(png), let pixels = raster(image), let originalBounds = pixels.bounds() else { return nil }
        original = image
        let edge = pixels.edgeBackground()
        let cleaned = edge.flatMap { pixels.removingEdgeBackground($0) }
        let art = cleaned ?? pixels
        backdrop = cleaned != nil ? edge : nil
        dominant = art.dominantColor()
        smartColor = art.smartBackground()
        separate = cleaned != nil || originalBounds.width < 256 || originalBounds.height < 256 || hasTransparentPixels(png)
        let logoBounds = art.bounds() ?? originalBounds
        bounds = logoBounds
        let data = Data(art.rgba)
        guard let provider = CGDataProvider(data: data as CFData), let cg = CGImage(width: 256, height: 256, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 1024, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: iconBitmapInfo), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let rect = CGRect(x: logoBounds.x, y: logoBounds.y, width: logoBounds.width, height: logoBounds.height)
        foreground = cg.cropping(to: rect) ?? cg
    }
}
func composeArtwork(_ art: IconArtwork, background: IconBackground, color: NSColor, inset: Double, lightening: Double) -> Data? {
    let fill: NSColor?
    switch background {
    case .original: fill = art.backdrop.map(nsColor)
    case .transparent: fill = nil
    case .white: fill = .white
    case .custom: fill = color
    case .smart: fill = nsColor(art.smartColor)
    case .automatic: fill = nsColor((art.dominant ?? IconRGB(r: 128, g: 128, b: 128)).lightened(max(0.30, min(0.50, lightening))))
    }
    let bitmapInfo = fill == nil ? iconBitmapInfo : (CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
    guard let ctx = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 1024, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) else { return nil }
    if let fill {
        ctx.setFillColor((fill.usingColorSpace(.deviceRGB) ?? .white).withAlphaComponent(1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
    }
    ctx.interpolationQuality = .high
    if !art.separate {
        // Complex opaque artwork cannot be separated reliably; never shrink it into a hard square.
        ctx.draw(art.original, in: CGRect(x: 0, y: 0, width: 256, height: 256))
    } else {
        let pad = CGFloat(max(0, min(0.30, inset))) * 256
        let side = 256 - 2*pad
        let scale = side / CGFloat(max(art.foreground.width, art.foreground.height))
        let w = CGFloat(art.foreground.width)*scale, h = CGFloat(art.foreground.height)*scale
        ctx.draw(art.foreground, in: CGRect(x: (256-w)/2, y: (256-h)/2, width: w, height: h))
    }
    guard let rendered = ctx.makeImage() else { return nil }
    let output = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, rendered, nil)
    return CGImageDestinationFinalize(dest) ? output as Data : nil
}

