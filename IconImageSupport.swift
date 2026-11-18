import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

private func cachedIconSource(_ data: Data) -> (CGImageSource, Int, Int)? {
    guard data.count <= 8_000_000, let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    var best = 0; var score = 0
    for i in 0..<min(CGImageSourceGetCount(src), 32) {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [String: Any], let w = props[kCGImagePropertyPixelWidth as String] as? Int, let h = props[kCGImagePropertyPixelHeight as String] as? Int, w > 0, h > 0, w <= 8192, h <= 8192 else { continue }
        if min(w,h) > score { score = min(w,h); best = i }
    }
    guard score > 0 else { return nil }
    return (src, best, score)
}
func cachedIconSize(_ data: Data) -> Int? {
    guard let (src, best, score) = cachedIconSource(data),
          CGImageSourceCreateThumbnailAtIndex(src, best, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 64, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil else { return nil }
    return score
}
func safePNG(_ data: Data) -> (Data, Int)? {
    guard let (src, best, score) = cachedIconSource(data), let image = CGImageSourceCreateThumbnailAtIndex(src, best, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary), let ctx = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let scale = 256 / CGFloat(max(image.width, image.height)); let w = CGFloat(image.width)*scale, h = CGFloat(image.height)*scale
    ctx.interpolationQuality = .high; ctx.draw(image, in: CGRect(x: (256-w)/2, y: (256-h)/2, width: w, height: h))
    guard let rendered = ctx.makeImage() else { return nil }; let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }; CGImageDestinationAddImage(dest, rendered, nil); guard CGImageDestinationFinalize(dest) else { return nil }; return (out as Data, score)
}
