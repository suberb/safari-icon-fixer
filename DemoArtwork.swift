import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Original geometric sample artwork, rendered in memory. No network or user file access.
func demoArtwork(_ id: Int, variant: Int = 0) -> Data {
    guard (0..<8).contains(id), variant >= 0 else { return Data() }
    guard let ctx = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 1024, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return Data() }
    let palette: [IconRGB] = [.init(r:169,g:38,b:99), .init(r:101,g:70,b:196), .init(r:19,g:125,b:96), .init(r:54,g:94,b:172), .init(r:158,g:90,b:10), .init(r:47,g:44,b:58), .init(r:38,g:114,b:138), .init(r:186,g:75,b:52)]
    let color = nsColor(palette[(id + variant % palette.count) % palette.count]).cgColor
    ctx.clear(CGRect(x: 0, y: 0, width: 256, height: 256)); ctx.setFillColor(color); ctx.setStrokeColor(color); ctx.setLineWidth(17); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    func line(_ pts: [CGPoint], close: Bool = false) { guard let first = pts.first else { return }; ctx.beginPath(); ctx.move(to: first); for p in pts.dropFirst() { ctx.addLine(to: p) }; if close { ctx.closePath(); ctx.fillPath() } else { ctx.strokePath() } }
    switch id {
    case 0: ctx.fill(CGRect(x: 63,y: 48,width: 34,height: 160)); ctx.fill(CGRect(x: 95,y: 174,width: 101,height: 34)); ctx.fill(CGRect(x: 95,y: 115,width: 77,height: 30))
    case 1: ctx.strokeEllipse(in: CGRect(x: 73,y: 73,width: 110,height: 110)); ctx.saveGState(); ctx.translateBy(x: 128,y: 128); ctx.rotate(by: .pi/4); ctx.strokeEllipse(in: CGRect(x: -92,y: -33,width: 184,height: 66)); ctx.restoreGState()
    case 2: line([CGPoint(x:42,y:128),CGPoint(x:89,y:186),CGPoint(x:128,y:66),CGPoint(x:169,y:154),CGPoint(x:214,y:154)])
    case 3: line([CGPoint(x:128,y:213),CGPoint(x:44,y:64),CGPoint(x:212,y:64)],close:true); ctx.setBlendMode(.clear); line([CGPoint(x:128,y:155),CGPoint(x:102,y:105),CGPoint(x:154,y:105)],close:true)
    case 4: for p in [CGPoint(x:85,y:128), CGPoint(x:155,y:128), CGPoint(x:120,y:93), CGPoint(x:120,y:163)] { ctx.fillEllipse(in:CGRect(x:p.x-39,y:p.y-39,width:78,height:78)) }
    case 5: for x in [58,139] { for y in [58,139] { ctx.fill(CGRect(x:CGFloat(x),y:CGFloat(y),width:59,height:59)) } }
    case 6: line([CGPoint(x:128,y:215),CGPoint(x:47,y:54),CGPoint(x:128,y:98),CGPoint(x:209,y:54)],close:true)
    default: ctx.fillEllipse(in:CGRect(x:89,y:89,width:78,height:78)); for step in 0..<8 { let angle = Double(step) * .pi/4; line([CGPoint(x:CGFloat(128+cos(angle)*62),y:CGFloat(128+sin(angle)*62)),CGPoint(x:CGFloat(128+cos(angle)*86),y:CGFloat(128+sin(angle)*86))]) }
    }
    guard let image = ctx.makeImage() else { return Data() }; let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return Data() }
    CGImageDestinationAddImage(dest,image,nil); return CGImageDestinationFinalize(dest) ? data as Data : Data()
}
