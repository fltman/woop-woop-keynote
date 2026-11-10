import SwiftUI

/// PDF och PNG ur samma SlideCanvas som allt annat ritar med.
@MainActor
public enum Snapshot {
    /// En PDF-sida per bild, 960×540 pt (samma mått som .pptx).
    public static func pdf(_ deck: Deck, assets: AssetStore) -> Data {
        let out = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: SlideSize.width / 2, height: SlideSize.height / 2)
        guard let consumer = CGDataConsumer(data: out),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        for slide in deck.slides {
            let r = ImageRenderer(content: SlideCanvas(slide: slide, assets: assets).environment(\.showsPlaceholders, false)
                .scaleEffect(0.5, anchor: .topLeading)
                .frame(width: box.width, height: box.height, alignment: .topLeading))
            ctx.beginPDFPage(nil)
            r.render { _, draw in draw(ctx) }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return out as Data
    }

    public static func image(_ slide: Slide, assets: AssetStore, width: Double = SlideSize.width) -> CGImage? {
        let r = ImageRenderer(content: SlideCanvas(slide: slide, assets: assets))
        r.scale = width / SlideSize.width
        return r.cgImage
    }
}
