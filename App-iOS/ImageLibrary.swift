import SwiftUI
import CloudKit
import ImageIO
import UniformTypeIdentifiers

/// Familjens gemensamma bibliotek med AI-bilder, i appens iCloud-behållare (CONTRACT §19).
/// Den gemensamma ("public") databasen nås bara av appar signerade med samma utvecklarkonto,
/// så i praktiken är den familjens. Varje bild sparas med beskrivningen och vem som gjorde den.
@MainActor @Observable
final class ImageLibrary {
    static let shared = ImageLibrary()

    struct Item: Identifiable {
        let id: CKRecord.ID
        let prompt: String
        let style: String
        let by: String
        let made: Date
        let thumb: UIImage?
        /// Bara den som gjorde bilden får ta bort den.
        let mine: Bool
    }

    private(set) var items: [Item] = []
    private(set) var loading = false
    private(set) var problem: String?
    /// Det senaste som gick fel när en bild skulle sparas (visas i biblioteket).
    private(set) var saveProblem: String?

    static let recordType = "GeneratedImage"
    static var containerID: String? {
        let v = (Bundle.main.object(forInfoDictionaryKey: "ICloudContainer") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return v.isEmpty || v.hasPrefix("$(") ? nil : v
    }
    private var db: CKDatabase? { Self.containerID.map { CKContainer(identifier: $0).publicCloudDatabase } }

    func refresh() async {
        guard let db else { problem = "Biblioteket är inte påslaget i den här versionen av appen."; return }
        loading = true
        defer { loading = false }
        // Frågan går på ett eget fält: att fråga efter "alla" kräver ett index som inte finns från början.
        let q = CKQuery(recordType: Self.recordType, predicate: NSPredicate(format: "kind == %@", "ai"))
        q.sortDescriptors = [NSSortDescriptor(key: "made", ascending: false)]
        do {
            let (results, _) = try await db.records(matching: q, desiredKeys: ["prompt", "style", "by", "made", "thumb"], resultsLimit: 120)
            items = results.compactMap { id, r in
                guard let rec = try? r.get() else { return nil }
                let thumb = (rec["thumb"] as? CKAsset)?.fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap(UIImage.init(data:))
                return Item(id: id, prompt: rec["prompt"] as? String ?? "", style: rec["style"] as? String ?? "",
                            by: rec["by"] as? String ?? "", made: rec["made"] as? Date ?? rec.creationDate ?? .distantPast,
                            thumb: thumb, mine: rec.creatorUserRecordID?.recordName == CKCurrentUserDefaultName)
            }
            problem = nil
        } catch let e as CKError where e.code == .unknownItem {
            items = []; problem = nil   // ingen har sparat något än
        } catch {
            problem = Self.explain(error)
        }
    }

    /// Sparar en bild som någon valt att använda. Körs i bakgrunden; ett fel stoppar inte presentationen.
    func save(_ image: Data, prompt: String, style: String, by: String) async {
        guard let db else { return }
        let dir = FileManager.default.temporaryDirectory
        let full = dir.appendingPathComponent("lib-\(UUID()).jpg"), thumb = dir.appendingPathComponent("lib-\(UUID())-t.jpg")
        defer { try? FileManager.default.removeItem(at: full); try? FileManager.default.removeItem(at: thumb) }
        guard let f = Self.jpeg(image, maxPixel: 1600), let t = Self.jpeg(image, maxPixel: 420),
              (try? f.write(to: full)) != nil, (try? t.write(to: thumb)) != nil else { return }
        let rec = CKRecord(recordType: Self.recordType)
        rec["kind"] = "ai"
        rec["prompt"] = String(prompt.prefix(500))
        rec["style"] = style
        rec["by"] = by
        rec["made"] = Date()
        rec["image"] = CKAsset(fileURL: full)
        rec["thumb"] = CKAsset(fileURL: thumb)
        do { _ = try await db.save(rec); saveProblem = nil }
        catch { saveProblem = "Senaste bilden sparades inte i biblioteket: " + Self.explain(error) }
    }

    func fullImage(_ item: Item) async throws -> Data {
        guard let db, let url = (try await db.record(for: item.id)["image"] as? CKAsset)?.fileURL else { throw CKError(.assetFileNotFound) }
        return try Data(contentsOf: url)
    }

    func delete(_ item: Item) async {
        guard let db else { return }
        do { _ = try await db.deleteRecord(withID: item.id); items.removeAll { $0.id == item.id } }
        catch { problem = Self.explain(error) }
    }

    static func explain(_ error: Error) -> String {
        guard let e = error as? CKError else { return "Något gick fel (\(error.localizedDescription))." }
        switch e.code {
        case .notAuthenticated: return "Logga in på iCloud i Inställningar för att spara bilder i biblioteket."
        case .networkUnavailable, .networkFailure, .serviceUnavailable: return "Ingen kontakt med iCloud just nu."
        case .quotaExceeded: return "iCloud-utrymmet är fullt."
        case .permissionFailure: return "Den här enheten får inte ändra i biblioteket."
        default: return "iCloud svarade med ett fel (\(e.code.rawValue): \(e.localizedDescription))."
        }
    }

    nonisolated static func jpeg(_ data: Data, maxPixel: Int) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(dst) ? out as Data : nil
    }
}

/// Rutnätet med familjens bilder. Tryck för att lägga en bild på den aktuella bilden.
struct ImageLibraryGrid: View {
    var onPick: (Data) -> Void
    @State private var library = ImageLibrary.shared
    @State private var fetching: CKRecord.ID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let p = library.problem ?? library.saveProblem {
                    Label(p, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red)
                }
                if library.items.isEmpty && !library.loading && library.problem == nil {
                    ContentUnavailableView("Inga bilder än", systemImage: "photo.stack",
                                           description: Text("Bilder som ni gör och lägger på en bild hamnar här, så att alla i familjen kan använda dem."))
                        .padding(.top, 40)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 14) {
                    ForEach(library.items) { item in
                        Button { Task { await pick(item) } } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground))
                                    if let t = item.thumb { Image(uiImage: t).resizable().scaledToFill() }
                                    if fetching == item.id { Color.black.opacity(0.35); ProgressView().tint(.white) }
                                }
                                .frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 10))
                                Text(item.prompt).font(.caption).lineLimit(2).multilineTextAlignment(.leading)
                                Text("\(item.by) · \(item.made.formatted(.relative(presentation: .named)))")
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if item.mine {
                                Button("Ta bort ur biblioteket", systemImage: "trash", role: .destructive) { Task { await library.delete(item) } }
                            }
                        }
                        .accessibilityLabel("\(item.prompt), gjord av \(item.by)")
                    }
                }
                if library.loading { ProgressView().frame(maxWidth: .infinity).padding() }
            }
            .padding()
        }
        .refreshable { await library.refresh() }
        .task { await library.refresh() }
    }

    private func pick(_ item: ImageLibrary.Item) async {
        guard fetching == nil else { return }
        fetching = item.id
        defer { fetching = nil }
        if let data = try? await library.fullImage(item) { onPick(data) }
    }
}
