import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func decode(_ data: Data) -> CGImage {
    let src = CGImageSourceCreateWithData(data as CFData,nil)!
    return CGImageSourceCreateImageAtIndex(src,0,nil)!
}
func png(_ cg: CGImage) -> Data {
    let d = NSMutableData()
    let dest = CGImageDestinationCreateWithData(d as CFMutableData, UTType.png.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(dest,cg,nil)
    precondition(CGImageDestinationFinalize(dest))
    return d as Data
}
let source = CGContext(data:nil,width:256,height:256,bitsPerComponent:8,bytesPerRow:1024,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
source.setFillColor(NSColor.white.cgColor)
source.fill(CGRect(x:20,y:20,width:216,height:216))
source.setFillColor(NSColor(red:0,green:0.4,blue:1,alpha:1).cgColor)
source.fill(CGRect(x:90,y:90,width:76,height:76))
let art = IconArtwork(png(source.makeImage()!))!
precondition(art.separate && art.backdrop != nil)
let white = composeArtwork(art,background:.white,color:.white,inset:0.25,lightening:0.4)!
let automatic = composeArtwork(art,background:.automatic,color:.white,inset:0.25,lightening:0.4)!
let transparent = composeArtwork(art,background:.transparent,color:.white,inset:0.25,lightening:0.4)!
precondition(!hasTransparentPixels(white) && !hasTransparentPixels(automatic))
precondition(hasTransparentPixels(transparent))
precondition(decode(white).width == 256 && decode(white).height == 256)
print("OK: pełne tło białe i automatyczne / przezroczyste tło / PNG 256 px")
precondition(decode(white).alphaInfo == .none || decode(white).alphaInfo == .noneSkipLast || decode(white).alphaInfo == .noneSkipFirst)
precondition(decode(automatic).alphaInfo == .none || decode(automatic).alphaInfo == .noneSkipLast || decode(automatic).alphaInfo == .noneSkipFirst)
print("OK: solid backgrounds exported as opaque PNG")
