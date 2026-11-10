import Foundation
import Observation
import SlideKit

/// Presentationerna på enheten: Documents/Decks/<id>.json, bilderna i Documents/Assets.
@MainActor @Observable
final class Library {
    private(set) var decks: [Deck] = []
    let assets: AssetStore
    private let dir: URL
    @ObservationIgnored private var dirty: [UUID: Deck] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("Decks")
        assets = AssetStore(directory: docs.appendingPathComponent("Assets"))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        decks = files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Deck.self, from: Data(contentsOf: $0)) }
            .sorted { $0.modified > $1.modified }
    }

    /// Sparar med en kort fördröjning, så att en skrivning inte blir hundra filskrivningar.
    func save(_ deck: Deck) {
        dirty[deck.id] = deck
        if let i = decks.firstIndex(where: { $0.id == deck.id }) { decks[i] = deck } else { decks.insert(deck, at: 0) }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        for d in dirty.values {
            if let data = try? JSONEncoder().encode(d) {
                try? data.write(to: dir.appendingPathComponent("\(d.id).json"), options: .atomic)
            }
        }
        dirty.removeAll()
    }

    func create(theme: Theme, template: DeckTemplate = .empty) -> Deck {
        let d = template == .empty ? Deck.new(title: "Ny presentation", theme: theme) : template.makeDeck(theme: theme)
        save(d); flush()
        return d
    }

    /// En kopia som blir min egen (t.ex. av en presentation jag gått med i).
    func saveCopy(of deck: Deck) -> Deck {
        var d = deck
        d.id = UUID(); d.title = deck.title + " (kopia)"; d.modified = Date()
        save(d); flush()
        return d
    }

    func delete(_ deck: Deck) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(deck.id).json"))
        decks.removeAll { $0.id == deck.id }
    }
}
