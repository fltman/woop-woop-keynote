import Foundation
import ImageIO

/// En avkodad animerad GIF: färdiga rutor (ImageIO sköter sammanslagningen) och hur länge varje ruta visas.
public final class GIFAnimation: @unchecked Sendable {
    public let frames: [CGImage]
    public let delays: [Double]
    public let duration: Double

    /// nil om datan inte är en GIF med minst två rutor.
    public init?(data: Data, maxFrames: Int = 300) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let n = min(CGImageSourceGetCount(src), maxFrames)
        guard n > 1 else { return nil }
        var frames: [CGImage] = [], delays: [Double] = []
        for i in 0..<n {
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            var d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            // Som webbläsarna: orimligt korta tider blir 0,1 s.
            if d < 0.02 { d = 0.1 }
            frames.append(img); delays.append(d)
        }
        guard frames.count > 1 else { return nil }
        self.frames = frames
        self.delays = delays
        self.duration = delays.reduce(0, +)
    }

    /// Rutan som ska synas vid en viss tidpunkt (loopar för evigt).
    public func frame(at date: Date) -> CGImage {
        var t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
        for (i, d) in delays.enumerated() {
            if t < d { return frames[i] }
            t -= d
        }
        return frames[frames.count - 1]
    }
}
