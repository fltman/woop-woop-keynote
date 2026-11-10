import Foundation
import UniformTypeIdentifiers

extension NSItemProvider {
    /// Bytes för första representationen som passar typen (png, jpeg, webp, heic …).
    func data(for type: UTType) async -> Data? {
        await withCheckedContinuation { c in
            _ = loadDataRepresentation(for: type) { data, _ in c.resume(returning: data) }
        }
    }

    func string() async -> String? {
        await withCheckedContinuation { c in
            _ = loadObject(ofClass: NSString.self) { obj, _ in c.resume(returning: obj as? String) }
        }
    }
}
