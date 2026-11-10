import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Innehållsadresserade bilder (CONTRACT §7). ID = sha256 av bytes + filändelse ("ab12….png").
public final class AssetStore: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()
    private var cache: [String: CGImage] = [:]
    private var animations: [String: GIFAnimation] = [:]

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static func id(for data: Data, ext: String) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + "." + ext
    }

    public func url(_ id: String) -> URL { directory.appendingPathComponent(id) }
    public func has(_ id: String) -> Bool { FileManager.default.fileExists(atPath: url(id).path) }
    public func data(_ id: String) -> Data? { try? Data(contentsOf: url(id)) }

    /// Lagrar bytes som redan är normaliserade (t.ex. mottagna från värden).
    @discardableResult
    public func put(_ data: Data, id: String) throws -> String {
        if !has(id) { try data.write(to: url(id), options: .atomic) }
        return id
    }

    /// Importerar en godtycklig bild: skalar ned till max 2048 px och väljer png (alfa) eller jpg.
    public func importImage(_ data: Data, maxPixel: Int = 2048) throws -> String {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { throw AssetError.unreadable }
        // Animerade GIF:ar sparas orörda: annars försvinner rörelsen. PowerPoint och Keynote
        // spelar GIF:ar i .pptx, så det går att exportera (CONTRACT §2).
        if CGImageSourceGetCount(src) > 1, (CGImageSourceGetType(src) as String?) == UTType.gif.identifier,
           data.count <= 12 * 1024 * 1024 {
            return try put(data, id: Self.id(for: data, ext: "gif"))
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw AssetError.unreadable }
        let alpha: Bool = switch img.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
        let type: UTType = alpha ? .png : .jpeg
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { throw AssetError.unreadable }
        CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(dst) else { throw AssetError.unreadable }
        let bytes = out as Data
        return try put(bytes, id: Self.id(for: bytes, ext: alpha ? "png" : "jpg"))
    }

    /// Ljud sparas som de är (inspelningar är redan .m4a). Max 15 MB.
    public func importAudio(_ data: Data, ext: String) throws -> String {
        guard data.count <= 15 * 1024 * 1024 else { throw AssetError.tooLarge }
        return try put(data, id: Self.id(for: data, ext: ext.lowercased()))
    }

    /// Rutor och tider för en animerad GIF, nil för stillbilder.
    public func animation(_ id: String) -> GIFAnimation? {
        guard id.hasSuffix(".gif") else { return nil }
        lock.lock()
        if let a = animations[id] { lock.unlock(); return a }
        lock.unlock()
        guard let d = data(id), let a = GIFAnimation(data: d) else { return nil }
        lock.lock(); animations[id] = a; lock.unlock()
        return a
    }

    public func cgImage(_ id: String) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        if let c = cache[id] { return c }
        guard let d = data(id), let src = CGImageSourceCreateWithData(d as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        cache[id] = img
        return img
    }

    /// Pixelstorlek, för att placera en ny bild med rätt proportioner.
    public func pixelSize(_ id: String) -> (Int, Int)? {
        guard let i = cgImage(id) else { return nil }
        return (i.width, i.height)
    }
}

public enum AssetError: Error { case unreadable, tooLarge }
