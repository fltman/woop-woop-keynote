import XCTest
import ImageIO
@testable import SlideKit

@MainActor
final class GIFTests: XCTestCase {
    /// En riktig animerad GIF med tre färgrutor à 0,2 s.
    static func animatedGIF() -> Data {
        let out = NSMutableData()
        let dst = CGImageDestinationCreateWithData(out, "com.compuserve.gif" as CFString, 3, nil)!
        CGImageDestinationSetProperties(dst, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (r, g, b) in [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)] {
            let ctx = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
            CGImageDestinationAddImage(dst, ctx.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dst))
        return out as Data
    }

    func testAnimatedGIFStaysAnimatedAndExports() throws {
        let store = AssetStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("gif-\(UUID())"))
        let gif = Self.animatedGIF()
        let id = try store.importImage(gif)
        XCTAssertTrue(id.hasSuffix(".gif"), "animerad GIF ska inte göras om till png/jpg")
        XCTAssertEqual(store.data(id), gif, "bytes orörda")
        let anim = try XCTUnwrap(store.animation(id))
        XCTAssertEqual(anim.frames.count, 3)
        XCTAssertEqual(anim.duration, 0.6, accuracy: 0.01)
        // Rutorna byts med tiden och loopar.
        // Början på ett varv, räknat från den faktiska längden (flyttal gör 600/0,6 opålitligt).
        let t0 = Date(timeIntervalSinceReferenceDate: anim.duration * 1000 + 0.01)
        XCTAssertTrue(anim.frame(at: t0) === anim.frames[0])
        XCTAssertTrue(anim.frame(at: t0.addingTimeInterval(0.3)) === anim.frames[1])
        XCTAssertTrue(anim.frame(at: t0.addingTimeInterval(0.5)) === anim.frames[2])
        XCTAssertTrue(anim.frame(at: t0.addingTimeInterval(0.62)) === anim.frames[0])

        // Stillbild blir fortfarande png/jpg och har ingen animation.
        let still = try store.importImage(SyncTests.tinyPNG()!)
        XCTAssertFalse(still.hasSuffix(".gif"))
        XCTAssertNil(store.animation(still))

        // .pptx får med GIF:en som .gif med rätt typ.
        var deck = Deck.new(title: "G")
        deck.slides[0].elements.append(Element(frame: Frame(x: 0, y: 0, w: 400, h: 200), content: .image(ImageBox(assetID: id))))
        let pptx = try PPTXExporter.export(deck, assets: store)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gifx-\(UUID())")
        let zip = dir.appendingPathExtension("pptx")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try pptx.write(to: zip)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); p.arguments = ["-q", zip.path, "-d", dir.path]
        try p.run(); p.waitUntilExit()
        let media = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("ppt/media").path)
        XCTAssertTrue(media.contains { $0.hasSuffix(".gif") }, "media: \(media)")
        let gifInZip = try XCTUnwrap(media.first { $0.hasSuffix(".gif") })
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("ppt/media/\(gifInZip)")), gif)
    }
}
