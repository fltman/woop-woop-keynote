// Ritar Apple TV-ikonen (tre lager för parallaxeffekten) och hyllbilderna.
// Kör: swift tools/make-tv-icon.swift   (från repots rot)
import AppKit
import CoreText

enum Layer { case back, middle, front, flat }

func hex(_ h: UInt32) -> CGColor {
    CGColor(red: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1)
}

func card(_ ctx: CGContext, cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, angle: CGFloat, color: CGColor) {
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy); ctx.rotate(by: angle * .pi / 180)
    ctx.addPath(CGPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerWidth: h * 0.1, cornerHeight: h * 0.1, transform: nil))
    ctx.setFillColor(color); ctx.fillPath()
    ctx.restoreGState()
}

func draw(_ w: Int, _ h: Int, _ layer: Layer, title: Bool = false) -> Data {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: (layer == .back || layer == .flat ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
    let W = CGFloat(w), H = CGFloat(h)
    if layer == .back || layer == .flat {
        let g = CGGradient(colorsSpace: nil, colors: [hex(0x1B1464), hex(0x6F1E51)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
    }
    // Kortbunten: höjden styr storleken, så att den ser likadan ut i alla format.
    let u = H * 0.5, cx = title ? W * 0.3 : W / 2, cy = H / 2
    if layer == .middle || layer == .flat {
        card(ctx, cx: cx, cy: cy, w: u * 1.5, h: u * 0.9, angle: 15, color: hex(0xFF4757))
        card(ctx, cx: cx, cy: cy + u * 0.02, w: u * 1.5, h: u * 0.9, angle: 0, color: hex(0x1E90FF))
    }
    if layer == .front || layer == .flat {
        card(ctx, cx: cx + u * 0.1, cy: cy - u * 0.02, w: u * 1.6, h: u * 0.9, angle: -15, color: hex(0xFFC312))
        func text(_ s: String, size: CGFloat, at p: CGPoint, centered: Bool) {
            let font = NSFont(name: "AvenirNext-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor.white]))
            let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            ctx.textPosition = CGPoint(x: centered ? p.x - b.midX : p.x, y: p.y - b.midY)
            CTLineDraw(line, ctx)
        }
        text("W!", size: u * 0.62, at: CGPoint(x: cx + u * 0.1, y: cy - u * 0.02), centered: true)
        if title { text("Woop Woop", size: H * 0.2, at: CGPoint(x: W * 0.52, y: cy), centered: false) }
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: "App-tvOS/Assets.xcassets/App Icon & Top Shelf Image.brandassets")
let fm = FileManager.default
try? fm.removeItem(at: root)
func write(_ path: String, _ data: Data) {
    let u = root.appendingPathComponent(path)
    try! fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: u)
}
func json(_ path: String, _ s: String) { write(path, Data(s.utf8)) }
let info = #""info" : { "author" : "xcode", "version" : 1 }"#

json("Contents.json", """
{ "assets" : [
  { "filename" : "App Icon.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "400x240" },
  { "filename" : "App Icon - App Store.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "1280x768" },
  { "filename" : "Top Shelf Image Wide.imageset", "idiom" : "tv", "role" : "top-shelf-image-wide", "size" : "2320x720" },
  { "filename" : "Top Shelf Image.imageset", "idiom" : "tv", "role" : "top-shelf-image", "size" : "1920x720" }
], \(info) }
""")

for (stack, w, h, scales) in [("App Icon.imagestack", 400, 240, [1, 2]), ("App Icon - App Store.imagestack", 1280, 768, [1])] {
    json("\(stack)/Contents.json", """
    { "layers" : [ { "filename" : "Front.imagestacklayer" }, { "filename" : "Middle.imagestacklayer" }, { "filename" : "Back.imagestacklayer" } ], \(info) }
    """)
    for (name, layer) in [("Front", Layer.front), ("Middle", .middle), ("Back", .back)] {
        json("\(stack)/\(name).imagestacklayer/Contents.json", "{ \(info) }")
        let images = scales.map { #"{ "filename" : "\#(name.lowercased())@\#($0)x.png", "idiom" : "tv", "scale" : "\#($0)x" }"# }.joined(separator: ", ")
        json("\(stack)/\(name).imagestacklayer/Content.imageset/Contents.json", "{ \"images\" : [ \(images) ], \(info) }")
        for s in scales { write("\(stack)/\(name).imagestacklayer/Content.imageset/\(name.lowercased())@\(s)x.png", draw(w * s, h * s, layer)) }
    }
}
for (set, w) in [("Top Shelf Image.imageset", 1920), ("Top Shelf Image Wide.imageset", 2320)] {
    json("\(set)/Contents.json", """
    { "images" : [ { "filename" : "shelf@1x.png", "idiom" : "tv", "scale" : "1x" }, { "filename" : "shelf@2x.png", "idiom" : "tv", "scale" : "2x" } ], \(info) }
    """)
    for s in [1, 2] { write("\(set)/shelf@\(s)x.png", draw(w * s, 720 * s, .flat, title: true)) }
}
// En platt förhandsvisning att titta på.
try! draw(800, 480, .flat).write(to: URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/dev/null"))
print("klart")
