import Foundation

/// Minimal zip-skrivare: lagrar filerna okomprimerade ("stored"), vilket är giltigt för .pptx.
/// Inga beroenden (CONTRACT §6).
public struct ZipWriter {
    private struct Entry { let name: [UInt8]; let crc: UInt32; let size: UInt32; let offset: UInt32 }
    private var out = Data()
    private var entries: [Entry] = []

    public init() {}

    public mutating func add(_ path: String, _ data: Data) {
        let name = Array(path.utf8)
        let crc = CRC32.checksum(data)
        let size = UInt32(data.count)
        let offset = UInt32(out.count)
        // Lokal filhuvud
        out.u32(0x04034b50)
        out.u16(20)          // version som krävs
        out.u16(0x0800)      // flagga: UTF-8-namn
        out.u16(0)           // metod: stored
        out.u16(0); out.u16(0x21) // tid/datum (1980-01-01)
        out.u32(crc); out.u32(size); out.u32(size)
        out.u16(UInt16(name.count)); out.u16(0)
        out.append(contentsOf: name)
        out.append(data)
        entries.append(Entry(name: name, crc: crc, size: size, offset: offset))
    }

    public mutating func add(_ path: String, _ text: String) { add(path, Data(text.utf8)) }

    public func finish() -> Data {
        var d = out
        let cdStart = UInt32(d.count)
        for e in entries {
            d.u32(0x02014b50)
            d.u16(20); d.u16(20)
            d.u16(0x0800); d.u16(0)
            d.u16(0); d.u16(0x21)
            d.u32(e.crc); d.u32(e.size); d.u32(e.size)
            d.u16(UInt16(e.name.count)); d.u16(0); d.u16(0)
            d.u16(0); d.u16(0); d.u32(0)
            d.u32(e.offset)
            d.append(contentsOf: e.name)
        }
        let cdSize = UInt32(d.count) - cdStart
        d.u32(0x06054b50)
        d.u16(0); d.u16(0)
        d.u16(UInt16(entries.count)); d.u16(UInt16(entries.count))
        d.u32(cdSize); d.u32(cdStart)
        d.u16(0)
        return d
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { buf in
            for b in buf { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func u16(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    mutating func u32(_ v: UInt32) { u16(UInt16(v & 0xFFFF)); u16(UInt16(v >> 16)) }
}
