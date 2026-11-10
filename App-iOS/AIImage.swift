import SwiftUI
import PhotosUI
import SlideKit

/// Bilder gjorda av en bildmodell via OpenRouter. Det enda som lämnar enheten är beskrivningen
/// man skriver (CONTRACT §18). Nyckeln ligger i Config/Secrets.xcconfig, som aldrig checkas in.
enum AIImage {
    enum Style: String, CaseIterable, Identifiable {
        case cartoon, photo, watercolor, pixel, clay, poster
        var id: String { rawValue }
        var name: String {
            switch self {
            case .cartoon: "Tecknat"
            case .photo: "Foto"
            case .watercolor: "Akvarell"
            case .pixel: "Pixelkonst"
            case .clay: "3D-lera"
            case .poster: "Affisch"
            }
        }
        var prompt: String {
            switch self {
            case .cartoon: "Clean modern cartoon illustration, bold outlines, flat colours."
            case .photo: "Realistic photograph, natural light, sharp focus."
            case .watercolor: "Soft watercolour painting on textured paper."
            case .pixel: "Retro pixel art, limited palette, crisp pixels."
            case .clay: "Cute 3D clay render, soft studio lighting."
            case .poster: "Bold graphic poster, strong shapes, limited colour palette."
            }
        }
    }

    enum Shape: String, CaseIterable, Identifiable {
        case wide = "16:9", landscape = "4:3", square = "1:1", portrait = "3:4"
        var id: String { rawValue }
        var name: String {
            switch self {
            case .wide: "Bred"
            case .landscape: "Liggande"
            case .square: "Kvadrat"
            case .portrait: "Stående"
            }
        }
    }

    static var apiKey: String? { setting("OpenRouterAPIKey") }
    static var model: String { setting("OpenRouterImageModel") ?? "google/gemini-3.1-flash-image" }
    /// Snabb textmodell för trollstaven som skriver om beskrivningar (svarar på ungefär en sekund).
    static var textModel: String { setting("OpenRouterTextModel") ?? "google/gemini-3.5-flash-lite" }

    private static func setting(_ key: String) -> String? {
        let v = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return v.isEmpty || v.hasPrefix("$(") ? nil : v
    }

    /// Bilder kostar pengar: ett tak per enhet och dag, så att en ivrig kväll inte blir dyr.
    static let dailyLimit = 30
    private static var todayKey: String { "aiImages-" + Date().formatted(.iso8601.year().month().day()) }
    static var usedToday: Int { UserDefaults.standard.integer(forKey: todayKey) }

    /// Ramarna modellen får: det här är för barn och ungdomar, till en presentation.
    private static let rules = """
    You make images for school presentations created by children and teenagers aged 11 to 16. \
    Always produce exactly one image and no text reply. Keep everything friendly and suitable for children: \
    no gore, horror, nudity, weapons pointed at people, drugs, or hateful content, and no realistic depictions of real, \
    named people. If the request does not fit, make a harmless, kind version of the idea instead. \
    Do not put text in the image unless the request asks for text.
    """

    /// Vad trollstaven hjälper till med. Varje fält där man beskriver något för en modell får en egen instruktion.
    enum Purpose {
        case image, imageWithReference
        var instruction: String {
            switch self {
            case .image: """
                Du hjälper barn och ungdomar 11–16 år att beskriva en bild som en bildmodell ska rita till en skolpresentation. \
                Skriv om beskrivningen så att den blir tydligare och mer målande: motiv, miljö, ljus, stämning och bildvinkel. \
                Behåll idén och hitta inte på ett annat motiv. Svara på svenska med högst två meningar, utan citattecken \
                och utan förklaringar. Nämn ingen stil (den väljs separat). Håll det barnvänligt.
                """
            case .imageWithReference: """
                Du hjälper barn och ungdomar 11–16 år att beskriva hur en bildmodell ska göra om en bild de har bifogat. \
                Skriv om önskemålet så att det blir tydligt vad som ska ändras och vad som ska vara kvar från originalbilden. \
                Behåll idén. Svara på svenska med högst två meningar, utan citattecken och utan förklaringar. \
                Nämn ingen stil (den väljs separat). Håll det barnvänligt.
                """
            }
        }
    }

    /// Trollstaven: skriver om det man skrivit till en bättre beskrivning.
    static func refine(_ text: String, purpose: Purpose, key: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": textModel, "max_tokens": 1500,
            "messages": [["role": "system", "content": purpose.instruction], ["role": "user", "content": String(text.prefix(600))]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Problem.http(status) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any],
              let out = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty else { throw Problem.noText }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "\"”“"))
    }

    /// `reference`: en bild att utgå från (görs om enligt beskrivningen). Den skickas till bildtjänsten.
    static func generate(_ description: String, style: Style, shape: Shape, reference: Data? = nil, key: String) async throws -> Data {
        guard usedToday < dailyLimit else { throw Problem.limit }
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "modalities": ["image", "text"],
            "image_config": ["aspect_ratio": shape.rawValue],
            "messages": [
                ["role": "system", "content": rules],
                ["role": "user", "content": userContent(description, style: style, reference: reference)],
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Problem.http(status) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (json["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any],
              let url = ((message["images"] as? [[String: Any]])?.first?["image_url"] as? [String: Any])?["url"] as? String,
              let comma = url.firstIndex(of: ","), let image = Data(base64Encoded: String(url[url.index(after: comma)...])) else {
            // Modellen svarade med text i stället för en bild: oftast för att den inte ville rita det.
            throw Problem.noImage
        }
        UserDefaults.standard.set(usedToday + 1, forKey: todayKey)
        return image
    }

    private static func userContent(_ description: String, style: Style, reference: Data?) -> Any {
        guard let ref = reference.flatMap({ ImageLibrary.jpeg($0, maxPixel: 1024) }) else {
            return "\(description)\n\nStyle: \(style.prompt)"
        }
        return [
            ["type": "text", "text": "Use the attached image as the reference and change it like this: \(description)\n\nStyle: \(style.prompt)"],
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + ref.base64EncodedString()]],
        ]
    }

    enum Problem: LocalizedError {
        case http(Int), noImage, noText, limit
        var errorDescription: String? {
            switch self {
            case .http(401), .http(403): "OpenRouter godkände inte nyckeln."
            case .http(402): "Pengarna på OpenRouter-kontot är slut."
            case .http(429): "För många bilder just nu. Vänta en stund."
            case .http(let c): "Det gick inte (fel \(c)). Försök igen."
            case .noImage: "Det blev ingen bild. Prova att beskriva den på ett annat sätt."
            case .noText: "Det gick inte att skriva om texten. Försök igen."
            case .limit: "Nu har den här enheten gjort \(AIImage.dailyLimit) bilder i dag. Fortsätt i morgon!"
            }
        }
    }
}

/// Beskriv en bild, välj stil och form, titta på resultatet och lägg den på bilden.
/// Ett fält där man beskriver något för en modell, med en trollstav som skriver om texten till en
/// bättre beskrivning. Används överallt där man "promptar". Ångra tar tillbaka det man själv skrev.
struct PromptField: View {
    var placeholder: String
    @Binding var text: String
    var purpose: AIImage.Purpose
    @State private var working = false
    @State private var before: String?
    @State private var problem: String?
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(2...6).focused($typing)
                if let key = AIImage.apiKey {
                    Button { Task { await refine(key) } } label: {
                        ZStack {
                            if working { ProgressView() } else { Image(systemName: "wand.and.stars").font(.title3) }
                        }
                        .frame(width: 40, height: 40)
                        .foregroundStyle(.white)
                        .background(Color.purple.opacity(canRefine ? 1 : 0.35), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canRefine)
                    .accessibilityLabel("Förbättra beskrivningen")
                }
            }
            .padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            if let before, before != text {
                Button { text = before; self.before = nil } label: {
                    Label("Ångra, ta tillbaka min text", systemImage: "arrow.uturn.backward").font(.caption.bold())
                }
            }
            if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
        }
        .onChange(of: typing) { _, t in if !t { problem = nil } }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("-wand"), before == nil, let key = AIImage.apiKey { await refine(key) }
        }
        #endif
    }

    private var canRefine: Bool { !working && text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 }

    private func refine(_ key: String) async {
        working = true; problem = nil
        defer { working = false }
        let mine = text
        do {
            text = try await AIImage.refine(mine, purpose: purpose, key: key)
            before = mine
        } catch let p as AIImage.Problem { problem = p.localizedDescription }
        catch { problem = "Ingen kontakt med tjänsten. Försök igen." }
    }
}

struct AIImageSheet: View {
    /// En bild att utgå från, t.ex. den som är markerad i redigeraren.
    var startReference: Data? = nil
    var onPick: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    /// Gör en ny bild, eller välj en som någon i familjen redan har gjort.
    @State private var showLibrary = ProcessInfo.processInfo.arguments.contains("bibliotek")
    @State private var text = AIImageSheet.debugPrompt
    @State private var style = AIImage.Style.cartoon
    @State private var shape = AIImage.Shape.landscape
    @State private var working = false
    @State private var result: Data?
    @State private var problem: String?
    @State private var reference: Data?
    @State private var photo: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Group {
                if showLibrary {
                    ImageLibraryGrid { data in onPick(data); dismiss() }
                } else if let key = AIImage.apiKey { form(key) } else {
                    ContentUnavailableView {
                        Label("OpenRouter-nyckel saknas", systemImage: "key")
                    } description: {
                        Text("Lägg OPENROUTER_API_KEY i Config/Secrets.xcconfig och bygg om appen.")
                    }
                }
            }
            .navigationTitle("Gör en bild")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                if ImageLibrary.containerID != nil {
                    ToolbarItem(placement: .principal) {
                        Picker("Visa", selection: $showLibrary) {
                            Text("Gör en ny").tag(false)
                            Text("Bibliotek").tag(true)
                        }
                        .pickerStyle(.segmented).frame(width: 230)
                    }
                }
            }
        }
    }

    private func form(_ key: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground))
                    if let result, let ui = UIImage(data: result) {
                        Image(uiImage: ui).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)).padding(8)
                    } else if working {
                        VStack(spacing: 12) { ProgressView().controlSize(.large); Text("Ritar … det tar ungefär tio sekunder").font(.footnote).foregroundStyle(.secondary) }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "wand.and.stars").font(.system(size: 44)).foregroundStyle(.purple)
                            Text("Beskriv bilden du vill ha").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 240)

                PromptField(placeholder: reference == nil ? "Till exempel: en vulkan som får utbrott i solnedgången"
                                                          : "Vad ska ändras? Till exempel: gör om den till vinter",
                            text: $text, purpose: reference == nil ? .image : .imageWithReference)

                referenceRow

                chips("Stil", AIImage.Style.allCases, selected: $style) { $0.name }
                chips("Form", AIImage.Shape.allCases, selected: $shape) { $0.name }

                if let problem { Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red) }

                if result == nil {
                    Button { Task { await make(key) } } label: {
                        Label("Gör bilden", systemImage: "wand.and.stars").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(.purple)
                    .disabled(working || text.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                } else {
                    HStack(spacing: 12) {
                        Button { Task { await make(key) } } label: {
                            Label("Gör en ny", systemImage: "arrow.clockwise").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered).disabled(working)
                        Button {
                            if let result {
                                onPick(result)
                                // Bilder man faktiskt använder hamnar i familjens bibliotek.
                                let (p, s, by) = (text, style.name, model.profile.name)
                                Task { await ImageLibrary.shared.save(result, prompt: p, style: s, by: by) }
                            }
                            dismiss()
                        } label: {
                            Label("Lägg på bilden", systemImage: "checkmark").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                Text("Beskrivningen skickas till en bildtjänst på internet. Skriv inga namn eller annat privat. Bilder du lägger på en bild sparas i familjens bibliotek. \(AIImage.dailyLimit - AIImage.usedToday) bilder kvar i dag.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if reference == nil { reference = startReference } }
        .onChange(of: photo) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                reference = ImageLibrary.jpeg(data, maxPixel: 1024)
                photo = nil; result = nil
            }
        }
        #if DEBUG
        // Med -aiimage görs bilden direkt, så att hela flödet går att se på simulatorn.
        .task { if !Self.debugPrompt.isEmpty, result == nil, !working, !ProcessInfo.processInfo.arguments.contains("-wand") { await make(key) } }
        #endif
    }

    /// Referensbild: modellen utgår från den och gör om den enligt beskrivningen.
    private var referenceRow: some View {
        HStack(spacing: 12) {
            if let reference, let ui = UIImage(data: reference) {
                Image(uiImage: ui).resizable().scaledToFill().frame(width: 64, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Utgår från den här bilden").font(.subheadline.bold())
                    Text("Bilden skickas till bildtjänsten. Använd inte foton på personer.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Ta bort referensbilden", systemImage: "xmark.circle.fill") { self.reference = nil; result = nil }
                    .labelStyle(.iconOnly).font(.title3).foregroundStyle(.secondary)
            } else {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Utgå från en bild (valfritt)", systemImage: "photo.badge.plus").font(.subheadline.bold())
                }
                Spacer(minLength: 0)
            }
        }
        .padding(reference == nil ? 0 : 10)
        .background(reference == nil ? Color.clear : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func chips<T: Identifiable & Equatable>(_ title: String, _ all: [T], selected: Binding<T>, name: @escaping (T) -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(all) { v in
                        Button { selected.wrappedValue = v } label: {
                            Text(name(v)).font(.subheadline.bold())
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .foregroundStyle(v == selected.wrappedValue ? Color.white : Color.primary)
                                .background(v == selected.wrappedValue ? Color.purple : Color(.secondarySystemBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(v == selected.wrappedValue ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func make(_ key: String) async {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        working = true; problem = nil; result = nil
        defer { working = false }
        do { result = try await AIImage.generate(text, style: style, shape: shape, reference: reference, key: key) }
        catch let p as AIImage.Problem { problem = p.localizedDescription }
        catch { problem = "Ingen kontakt med bildtjänsten. Kolla internet och försök igen." }
    }

    /// Startflaggan -aiimage <beskrivning> öppnar rutan ifylld (bara debug, för simulatorn).
    static var debugPrompt: String {
        #if DEBUG
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-aiimage"), i + 1 < a.count, a[i + 1] != "bibliotek" { return a[i + 1] }
        #endif
        return ""
    }
}
