import SwiftUI
import ImageIO
import SlideKit

/// Sökning hos GIPHY. Bara barnvänligt innehåll (rating=g).
/// Det enda som lämnar enheten är sökorden (CONTRACT §13).
enum Giphy {
    enum Kind: String, CaseIterable, Identifiable {
        case gifs, stickers
        var id: String { rawValue }
        var name: String { self == .gifs ? "GIF" : "Klistermärken" }
    }

    struct Item: Identifiable, Hashable {
        let id: String
        let title: String
        let preview: URL      // liten, animerad
        let full: URL         // högst ~2 MB
        let width: Double
        let height: Double
    }

    static var apiKey: String? {
        let k = (Bundle.main.object(forInfoDictionaryKey: "GiphyAPIKey") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return k.isEmpty || k.hasPrefix("$(") ? nil : k
    }

    private struct Response: Decodable {
        struct G: Decodable {
            let id: String
            let title: String?
            let images: [String: Rendition]
        }
        struct Rendition: Decodable {
            let url: String?
            let width: String?
            let height: String?
        }
        let data: [G]
    }

    static func search(_ query: String, kind: Kind, key: String) async throws -> [Item] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var c = URLComponents(string: "https://api.giphy.com/v1/\(kind.rawValue)/\(q.isEmpty ? "trending" : "search")")!
        c.queryItems = [
            .init(name: "api_key", value: key),
            .init(name: "limit", value: "36"),
            .init(name: "rating", value: "g"),
            .init(name: "lang", value: "sv"),
        ] + (q.isEmpty ? [] : [.init(name: "q", value: q)])
        let (data, resp) = try await URLSession.shared.data(from: c.url!)
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 { throw GiphyError.http(h.statusCode) }
        return try JSONDecoder().decode(Response.self, from: data).data.compactMap { g in
            let small = g.images["fixed_width_small"] ?? g.images["fixed_width"]
            let big = g.images["downsized"] ?? g.images["fixed_width"]
            guard let p = small?.url.flatMap(URL.init), let f = big?.url.flatMap(URL.init) else { return nil }
            return Item(id: g.id, title: g.title ?? "", preview: p, full: f,
                        width: Double(big?.width ?? "") ?? 1, height: Double(big?.height ?? "") ?? 1)
        }
    }

    enum GiphyError: LocalizedError {
        case http(Int)
        var errorDescription: String? {
            switch self {
            case .http(401), .http(403): "GIPHY godkände inte nyckeln."
            case .http(429): "För många sökningar just nu – vänta en stund."
            case .http(let c): "GIPHY svarade med fel \(c)."
            }
        }
    }
}

/// Sök och välj en GIF eller ett klistermärke. Valet hämtas och lämnas tillbaka som data.
struct GiphyPicker: View {
    var onPick: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = GiphyPicker.debugQuery
    @State private var kind: Giphy.Kind = .gifs
    @State private var items: [Giphy.Item] = []
    @State private var error: String?
    @State private var downloading: String?

    var body: some View {
        NavigationStack {
            Group {
                if let key = Giphy.apiKey {
                    grid
                        .task(id: "\(kind.rawValue)|\(query)") {
                            // Vänta tills man slutat skriva en stund.
                            try? await Task.sleep(nanoseconds: query.isEmpty ? 0 : 400_000_000)
                            guard !Task.isCancelled else { return }
                            do { items = try await Giphy.search(query, kind: kind, key: key); error = nil }
                            catch is CancellationError {}
                            catch { self.error = error.localizedDescription }
                        }
                } else {
                    ContentUnavailableView {
                        Label("GIPHY-nyckel saknas", systemImage: "key")
                    } description: {
                        Text("Skapa en gratis nyckel på developers.giphy.com och lägg den i Config/Secrets.xcconfig.")
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Sök på GIPHY")
            .navigationTitle("GIPHY")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    Picker("Sort", selection: $kind) {
                        ForEach(Giphy.Kind.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented).frame(width: 260)
                }
            }
        }
    }

    /// Startflaggan -giphy <sökord> öppnar rutan med ett sökord (bara debug, för att prova på simulatorn).
    static var debugQuery: String {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-giphy"), i + 1 < a.count { return a[i + 1] }
        #endif
        return ""
    }

    private var grid: some View {
        ScrollView {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).padding()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                ForEach(items) { item in
                    Button { Task { await pick(item) } } label: {
                        GiphyCell(url: item.preview, checkered: kind == .stickers)
                            .aspectRatio(item.width / max(item.height, 1), contentMode: .fit)
                            .frame(maxWidth: .infinity, minHeight: 80)
                            .overlay { if downloading == item.id { ProgressView().controlSize(.large) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title.isEmpty ? "GIF" : item.title)
                }
            }
            .padding(8)
            // GIPHY kräver att det syns var bilderna kommer ifrån.
            Text("Drivs av GIPHY").font(.caption.bold()).foregroundStyle(.secondary).padding(.bottom, 20)
        }
    }

    private func pick(_ item: Giphy.Item) async {
        guard downloading == nil else { return }
        downloading = item.id
        defer { downloading = nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: item.full)
            onPick(data)
            dismiss()
        } catch {
            self.error = "Kunde inte hämta: \(error.localizedDescription)"
        }
    }
}

/// En liten förhandsvisning som rör sig.
private struct GiphyCell: View {
    let url: URL
    var checkered: Bool
    @State private var animation: GIFAnimation?
    @State private var still: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(checkered ? Color.gray.opacity(0.35) : Color.gray.opacity(0.15))
            if let animation { AnimatedImage(animation: animation).scaledToFit() }
            else if let still { Image(decorative: still, scale: 1).resizable().scaledToFit() }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: url) {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            if let a = GIFAnimation(data: data) { animation = a }
            else if let src = CGImageSourceCreateWithData(data as CFData, nil) { still = CGImageSourceCreateImageAtIndex(src, 0, nil) }
        }
    }
}
