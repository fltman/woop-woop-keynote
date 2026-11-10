import Foundation
import CloudKit
import Observation
import SlideKit

/// Säkerhetskopia av presentationerna i varje persons EGEN iCloud (CloudKits privata databas).
/// Tappas telefonen bort finns presentationerna kvar och går att hämta hem på en ny enhet (CONTRACT §20).
/// Ett fel mot iCloud får aldrig störa arbetet: allt här är "om det går".
@MainActor @Observable
final class DeckBackup {
    struct CloudDeck: Identifiable, Hashable {
        let id: UUID
        let title: String
        let modified: Date
    }

    /// Presentationer som finns i iCloud (även de som också finns på enheten).
    private(set) var cloud: [CloudDeck] = []
    private(set) var problem: String?
    private(set) var restoring: UUID?

    private let assets: AssetStore
    @ObservationIgnored private var pending: [UUID: Task<Void, Never>] = [:]
    private var db: CKDatabase? { ImageLibrary.containerID.map { CKContainer(identifier: $0).privateCloudDatabase } }

    init(assets: AssetStore) { self.assets = assets }

    private static func deckID(_ id: UUID) -> CKRecord.ID { CKRecord.ID(recordName: "deck-\(id.uuidString)") }
    private static func assetID(_ id: String) -> CKRecord.ID { CKRecord.ID(recordName: "asset-\(id)") }
    /// Filer som redan ligger i iCloud, så att de inte laddas upp igen.
    private var uploaded: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "backupAssets") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "backupAssets") }
    }

    /// Laddar upp en stund efter senaste ändringen, så att varje bokstav inte blir en uppladdning.
    func schedule(_ deck: Deck) {
        guard db != nil else { return }
        pending[deck.id]?.cancel()
        pending[deck.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.upload(deck)
        }
    }

    private func upload(_ deck: Deck) async {
        guard let db, let json = try? JSONEncoder().encode(deck) else { return }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("deck-\(deck.id).json")
        defer { try? FileManager.default.removeItem(at: file) }
        guard (try? json.write(to: file)) != nil else { return }
        var records: [CKRecord] = []
        let rec = CKRecord(recordType: "Deck", recordID: Self.deckID(deck.id))
        rec["kind"] = "deck"; rec["title"] = deck.title; rec["modified"] = deck.modified
        rec["json"] = CKAsset(fileURL: file)
        records.append(rec)
        var done = uploaded
        let missing = deck.assetIDs.filter { !done.contains($0) && assets.has($0) }
        for id in missing {
            let a = CKRecord(recordType: "DeckAsset", recordID: Self.assetID(id))
            a["file"] = CKAsset(fileURL: assets.url(id))
            records.append(a)
        }
        do {
            // Ersätt det som redan finns (samma post-id), i stället för att krocka med serverns version.
            _ = try await db.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
            done.formUnion(missing); uploaded = done
            problem = nil
            if let i = cloud.firstIndex(where: { $0.id == deck.id }) { cloud[i] = CloudDeck(id: deck.id, title: deck.title, modified: deck.modified) }
            else { cloud.insert(CloudDeck(id: deck.id, title: deck.title, modified: deck.modified), at: 0) }
        } catch { problem = "Säkerhetskopian i iCloud: " + ImageLibrary.explain(error) }
    }

    func refresh() async {
        guard let db else { return }
        let q = CKQuery(recordType: "Deck", predicate: NSPredicate(format: "kind == %@", "deck"))
        q.sortDescriptors = [NSSortDescriptor(key: "modified", ascending: false)]
        do {
            let (results, _) = try await db.records(matching: q, desiredKeys: ["title", "modified"], resultsLimit: 200)
            cloud = results.compactMap { id, r in
                guard let rec = try? r.get(), let uuid = UUID(uuidString: String(id.recordName.dropFirst(5))) else { return nil }
                return CloudDeck(id: uuid, title: rec["title"] as? String ?? "Presentation", modified: rec["modified"] as? Date ?? .distantPast)
            }
            problem = nil
        } catch let e as CKError where e.code == .unknownItem || e.code == .notAuthenticated {
            cloud = []; problem = e.code == .notAuthenticated ? "Logga in på iCloud för att få säkerhetskopior." : nil
        } catch { problem = "Säkerhetskopian i iCloud: " + ImageLibrary.explain(error) }
    }

    /// Hämtar hem en presentation och bilderna den använder.
    func restore(_ item: CloudDeck) async -> Deck? {
        guard let db else { return nil }
        restoring = item.id
        defer { restoring = nil }
        do {
            let rec = try await db.record(for: Self.deckID(item.id))
            guard let url = (rec["json"] as? CKAsset)?.fileURL,
                  let deck = try? JSONDecoder().decode(Deck.self, from: Data(contentsOf: url)) else { return nil }
            let missing = deck.assetIDs.filter { !assets.has($0) }
            if !missing.isEmpty {
                let found = try await db.records(for: missing.map(Self.assetID))
                for id in missing {
                    if case .success(let a)? = found[Self.assetID(id)], let f = (a["file"] as? CKAsset)?.fileURL, let d = try? Data(contentsOf: f) {
                        _ = try? assets.put(d, id: id)
                    }
                }
            }
            return deck
        } catch { problem = "Kunde inte hämta presentationen: " + ImageLibrary.explain(error); return nil }
    }

    func delete(_ id: UUID) {
        pending[id]?.cancel()
        cloud.removeAll { $0.id == id }
        guard let db else { return }
        Task { _ = try? await db.deleteRecord(withID: Self.deckID(id)) }
    }
}
