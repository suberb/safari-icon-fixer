import Foundation

struct IconRGB: Equatable {
    var r: Int; var g: Int; var b: Int
    func distance(_ other: IconRGB) -> Int { max(abs(r-other.r), max(abs(g-other.g), abs(b-other.b))) }
    func lightened(_ fraction: Double) -> IconRGB {
        let f = max(0, min(1, fraction))
        func channel(_ v: Int) -> Int { Int((Double(v) + (255-Double(v))*f).rounded()) }
        return IconRGB(r: channel(r), g: channel(g), b: channel(b))
    }
}
struct IconBounds: Equatable { var x: Int; var y: Int; var width: Int; var height: Int }
struct IconRaster {
    let width: Int; let height: Int
    var rgba: [UInt8] // premultiplied RGBA
    func alpha(_ p: Int) -> Int { Int(rgba[p*4+3]) }
    func rgb(_ p: Int) -> IconRGB {
        let i = p*4; let a = max(1, alpha(p))
        return IconRGB(r: min(255,Int(rgba[i])*255/a), g: min(255,Int(rgba[i+1])*255/a), b: min(255,Int(rgba[i+2])*255/a))
    }
    func bounds() -> IconBounds? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for p in 0..<(width*height) where alpha(p) > 12 {
            let x = p % width, y = p / width
            minX = min(minX,x); minY = min(minY,y); maxX = max(maxX,x); maxY = max(maxY,y)
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return IconBounds(x: minX, y: minY, width: maxX-minX+1, height: maxY-minY+1)
    }
    // Only classify a sufficiently uniform, opaque perimeter as removable.
    // The bounding rectangle also handles transparent padding around an opaque tile.
    func edgeBackground() -> IconRGB? {
        guard let b = bounds(), b.width >= 8, b.height >= 8 else { return nil }
        // The second perimeter is slightly inset for rounded opaque tiles with alpha corners.
        for inset in [0, max(1, min(b.width, b.height)/12)] {
            var edge: [Int] = []
            let left = b.x+inset, topY = b.y+inset
            let right = b.x+b.width-1-inset, bottom = b.y+b.height-1-inset
            guard left < right, topY < bottom else { continue }
            for x in left...right { edge.append(topY*width+x); edge.append(bottom*width+x) }
            for y in topY...bottom { edge.append(y*width+left); edge.append(y*width+right) }
            let colors = edge.filter { alpha($0) >= 245 }.map { rgb($0) }
            guard colors.count * 10 >= edge.count * 7 else { continue }
            var bins: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
            for c in colors {
                let key = (c.r/24)*144+(c.g/24)*12+c.b/24
                let old = bins[key] ?? (0,0,0,0)
                bins[key] = (old.count+1, old.r+c.r, old.g+c.g, old.b+c.b)
            }
            guard let top = bins.max(by: { a,b in a.value.count == b.value.count ? a.key > b.key : a.value.count < b.value.count })?.value else { continue }
            let base = IconRGB(r: top.r/top.count, g: top.g/top.count, b: top.b/top.count)
            let similar = colors.filter { $0.distance(base) <= 28 }
            if similar.count * 10 >= edge.count * 7 { return base }
        }
        return nil
    }
    // Flood only pixels reachable from the outer edge. Preserve enclosed matching colors.
    func removingEdgeBackground(_ color: IconRGB) -> IconRaster? {
        var output = self
        var visited = [Bool](repeating: false, count: width*height)
        var queue: [Int] = []
        func visit(_ p: Int) {
            if visited[p] { return }; visited[p] = true
            if alpha(p) <= 12 || rgb(p).distance(color) <= 30 { queue.append(p) }
        }
        for x in 0..<width { visit(x); visit((height-1)*width+x) }
        for y in 0..<height { visit(y*width); visit(y*width+width-1) }
        var head = 0
        while head < queue.count {
            let p = queue[head]; head += 1
            for c in 0..<4 { output.rgba[p*4+c] = 0 }
            let x = p % width, y = p / width
            if x > 0 { visit(p-1) }; if x+1 < width { visit(p+1) }
            if y > 0 { visit(p-width) }; if y+1 < height { visit(p+width) }
        }
        guard output.bounds() != nil else { return nil }
        return output
    }
    func dominantColor() -> IconRGB? {
        var bins: [Int:(weight: Int, r: Int, g: Int, b: Int, count: Int)] = [:]
        var neutral: [Int:(weight: Int, r: Int, g: Int, b: Int, count: Int)] = [:]
        for p in 0..<(width*height) where alpha(p) >= 160 {
            let c = rgb(p); let hi = max(c.r,max(c.g,c.b)), lo = min(c.r,min(c.g,c.b))
            let sat = hi-lo
            let key = (c.r/32)*64+(c.g/32)*8+c.b/32
            let weight = alpha(p) * (sat+32)
            if sat >= 35 && hi >= 70 {
                let old = bins[key] ?? (0,0,0,0,0)
                bins[key] = (old.weight+weight,old.r+c.r,old.g+c.g,old.b+c.b,old.count+1)
            } else {
                let old = neutral[key] ?? (0,0,0,0,0)
                neutral[key] = (old.weight+weight,old.r+c.r,old.g+c.g,old.b+c.b,old.count+1)
            }
        }
        let source = bins.isEmpty ? neutral : bins
        guard let v = source.max(by: { a,b in a.value.weight == b.value.weight ? a.key > b.key : a.value.weight < b.value.weight })?.value else { return nil }
        return IconRGB(r:v.r/v.count,g:v.g/v.count,b:v.b/v.count)
    }
}

// Safari's private cache display styles; empirically documented, not an Apple API.
enum SafariIconDisplay: Int {
    case systemTile = 0
    case fullTile = 1
    var label: String { self == .fullTile ? l10n("Pełny kafelek") : l10n("Tło systemowe") }
}
func iconDisplayAssignment(_ style: SafariIconDisplay?) -> String {
    guard let style else { return "" }
    return ", transparency_analysis_result=\(style.rawValue)"
}
