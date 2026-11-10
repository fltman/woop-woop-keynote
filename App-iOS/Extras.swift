import SwiftUI
import Vision
import CoreImage
import AVFoundation
import SlideKit

// Små verktyg som flera vyer delar: ta bort bakgrund, komprimera video, öva, rityta, hjul och publikfrågor.

/// Tar bort bakgrunden ur en bild, helt på enheten (inget skickas någonstans).
enum BackgroundRemover {
    static func remove(_ data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let input = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
            let handler = VNImageRequestHandler(ciImage: input)
            let request = VNGenerateForegroundInstanceMaskRequest()
            guard (try? handler.perform([request])) != nil, let result = request.results?.first,
                  let buffer = try? result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
            else { return nil }
            let out = CIImage(cvPixelBuffer: buffer)
            return CIContext().pngRepresentation(of: out, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }.value
    }
}

/// Gör ett klipp litet nog att skicka till de andra: högst 20 sekunder, 540p.
enum VideoImport {
    static func mp4(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset960x540) else { return nil }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("klipp-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: out) }
        let length = (try? await asset.load(.duration)) ?? .zero
        export.timeRange = CMTimeRange(start: .zero, duration: CMTimeMinimum(length, CMTime(seconds: 20, preferredTimescale: 600)))
        export.shouldOptimizeForNetworkUse = true
        guard (try? await export.export(to: out, as: .mp4)) != nil else { return nil }
        return try? Data(contentsOf: out)
    }
}

/// Ett videoklipp från bildbiblioteket, som fil.
struct MovieFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("in-\(UUID()).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return MovieFile(url: copy)
        }
    }
}

// MARK: - Öva

/// Öva ensam: inget visas på TV:n. Appen tar tid per bild och visar efteråt var man pratade längst.
struct PracticeView: View {
    let deck: Deck
    let assets: AssetStore
    var startAt: Int
    @Environment(\.dismiss) private var dismiss
    @State private var state: PresentState
    @State private var entered = Date()
    @State private var times: [Int: TimeInterval] = [:]
    @State private var done = false

    init(deck: Deck, assets: AssetStore, startAt: Int) {
        self.deck = deck; self.assets = assets; self.startAt = startAt
        _state = State(initialValue: PresentState(isPresenting: true, slideIndex: startAt))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if done { summary } else { run }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }

    private var run: some View {
        VStack(spacing: 12) {
            HStack {
                Button { finish() } label: { Label("Klar", systemImage: "checkmark").font(.headline) }.buttonStyle(.bordered)
                Spacer()
                Text("Övar · bild \(state.slideIndex + 1) av \(deck.slides.count)").font(.headline.monospacedDigit())
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(clock(ctx.date.timeIntervalSince(entered))).font(.title3.bold().monospacedDigit())
                }
            }
            PresentationView(deck: deck, state: state, assets: assets, presenter: true, playsSound: true)
                .aspectRatio(SlideSize.width / SlideSize.height, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .onTapGesture { step(state.next(in: deck)) }
            ScrollView {
                Text(deck.slides[safe: state.slideIndex]?.notes.isEmpty == false ? deck.slides[state.slideIndex].notes : "Inga anteckningar till den här bilden.")
                    .font(.title3).frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 10) {
                Button { step(state.previous(in: deck)) } label: {
                    Image(systemName: "chevron.left").font(.title2.bold()).frame(width: 72, height: 64)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                }
                Button {
                    let next = state.next(in: deck)
                    if next == state { finish() } else { step(next) }
                } label: {
                    Text("Nästa").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 64)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .foregroundStyle(.white)
        }
        .padding(12)
    }

    private var summary: some View {
        let total = times.values.reduce(0, +)
        let longest = max(times.values.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Bra övat!").font(.largeTitle.bold())
            Text("Hela presentationen tog \(clock(total)).").font(.title3).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(deck.slides.indices, id: \.self) { i in
                        let t = times[i] ?? 0
                        HStack(spacing: 10) {
                            Text("\(i + 1)").font(.headline.monospacedDigit()).frame(width: 28)
                            SlideView(slide: deck.slides[i], assets: assets).environment(\.animatesImages, false)
                                .frame(width: 72).clipShape(RoundedRectangle(cornerRadius: 4))
                            GeometryReader { g in
                                RoundedRectangle(cornerRadius: 6).fill(t == longest && t > 0 ? Color.orange : Color.accentColor)
                                    .frame(width: max(g.size.width * t / longest, 4))
                            }
                            .frame(height: 22)
                            Text(clock(t)).font(.subheadline.monospacedDigit()).frame(width: 52, alignment: .trailing)
                        }
                    }
                }
            }
            Text("Den orangea bilden pratade du längst om.").font(.footnote).foregroundStyle(.secondary)
            Button { dismiss() } label: { Text("Stäng").font(.headline).frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    private func clock(_ t: TimeInterval) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }

    private func step(_ next: PresentState) {
        if next.slideIndex != state.slideIndex {
            times[state.slideIndex, default: 0] += Date().timeIntervalSince(entered)
            entered = Date()
        }
        state = next
    }

    private func finish() {
        times[state.slideIndex, default: 0] += Date().timeIntervalSince(entered)
        done = true
    }
}

// MARK: - Gemensam rityta

/// Alla ritar samtidigt från sina telefoner, och TV:n visar tavlan.
struct BoardView: View {
    let session: Session
    var onSave: ((Data, Frame) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var current: InkStroke?
    @State private var color: RGBA
    @State private var lastSent = Date.distantPast
    private static let colors = ["000000", "FF4757", "FFA502", "2ED573", "1E90FF", "A55EEA", "FF6B81"].map { RGBA(hex: $0) }

    init(session: Session, onSave: ((Data, Frame) -> Void)? = nil) {
        self.session = session; self.onSave = onSave
        _color = State(initialValue: session.me.color)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                GeometryReader { geo in
                    let k = geo.size.width / SlideSize.width
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(.white)
                        InkCanvas(strokes: session.live.ink, k: k)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let p = Spot(x: min(max(v.location.x / k, 0), SlideSize.width), y: min(max(v.location.y / k, 0), SlideSize.height))
                            var s = current ?? InkStroke(points: [], color: color, width: 12)
                            if let l = s.points.last, hypot(l.x - p.x, l.y - p.y) < 4 { return }
                            guard s.points.count < 600 else { return }
                            s.points.append(p)
                            current = s
                            guard Date().timeIntervalSince(lastSent) > 1 / 20 else { return }
                            lastSent = Date()
                            session.send(.stroke(s))
                        }
                        .onEnded { _ in
                            if let s = current { session.send(.stroke(s)) }
                            current = nil
                        })
                }
                .aspectRatio(SlideSize.width / SlideSize.height, contentMode: .fit)
                .shadow(radius: 6).padding(.horizontal, 12)
                HStack(spacing: 12) {
                    ForEach(Self.colors, id: \.self) { c in
                        Circle().fill(c.color).frame(width: 36, height: 36)
                            .overlay { Circle().stroke(.gray.opacity(0.5), lineWidth: 1) }
                            .overlay { if c == color { Circle().stroke(Color.accentColor, lineWidth: 3).padding(-5) } }
                            .onTapGesture { color = c }
                    }
                }
                if !session.live.board {
                    Text("Ritytan är stängd.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Rita tillsammans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Stäng") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Sudda allt", systemImage: "eraser") { session.send(.clearInk) }
                    if let onSave {
                        Button("Spara som bild", systemImage: "square.and.arrow.down") { save(onSave) }
                            .disabled(session.live.ink.isEmpty)
                    }
                }
            }
        }
    }

    /// Hela tavlan blir en genomskinlig bild på den aktuella bilden.
    private func save(_ done: (Data, Frame) -> Void) {
        let r = ImageRenderer(content: InkCanvas(strokes: session.live.ink, k: 1).frame(width: SlideSize.width, height: SlideSize.height))
        r.scale = 1; r.isOpaque = false
        if let png = r.uiImage?.pngData() { done(png, Frame(x: 0, y: 0, w: SlideSize.width, h: SlideSize.height)) }
        dismiss()
    }
}

// MARK: - Publiken: poäng, buzzer, hjul och frågor

/// Presentatörens meny för det som rör publiken.
struct AudienceMenu: View {
    let session: Session
    @State private var wheel = false
    @State private var questions = false

    var body: some View {
        Menu {
            Button(session.live.showScores ? "Göm poängställningen" : "Visa poängställningen", systemImage: "trophy.fill") {
                session.send(.showScores(!session.live.showScores))
            }
            Button(session.live.buzzerArmed || session.live.buzzWinner != nil ? "Stäng buzzern" : "Buzzer: först att trycka", systemImage: "bell.fill") {
                session.send(.buzzer(!(session.live.buzzerArmed || session.live.buzzWinner != nil)))
            }
            if session.live.wheel != nil {
                Button("Göm hjulet", systemImage: "xmark.circle") { session.send(.hideWheel) }
            } else {
                Button("Snurra hjulet …", systemImage: "arrow.triangle.2.circlepath.circle.fill") { wheel = true }
            }
            Button("Frågor från publiken (\(session.live.questions.count))", systemImage: "questionmark.bubble.fill") { questions = true }
            if session.live.shownQuestion != nil {
                Button("Göm frågan", systemImage: "xmark.circle") { session.send(.showQuestion(nil)) }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "person.3.fill").font(.body.bold())
                Text("Publik").font(.system(size: 10, weight: .bold))
            }
            .frame(width: 52, height: 48).foregroundStyle(.white)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                if !session.live.questions.isEmpty {
                    Text("\(session.live.questions.count)").font(.caption2.bold()).foregroundStyle(.white)
                        .padding(5).background(Color.red, in: Circle()).offset(x: 6, y: -6)
                }
            }
        }
        .accessibilityLabel("Publiken")
        .sheet(isPresented: $wheel) { WheelSheet(session: session) }
        .sheet(isPresented: $questions) { QuestionSheet(session: session) }
    }
}

struct WheelSheet: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var options: [String] {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("En sak per rad") { TextEditor(text: $text).frame(minHeight: 220) }
                Section {
                    Button { spin() } label: { Label("Snurra!", systemImage: "arrow.triangle.2.circlepath").font(.headline).frame(maxWidth: .infinity) }
                        .disabled(options.count < 2)
                } footer: { Text("Hjulet snurrar på presentationsskärmen och stannar på en av raderna.") }
            }
            .navigationTitle("Slumphjul").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Avbryt") { dismiss() } }
            .onAppear {
                if text.isEmpty {
                    // Förslag: alla som är med, och publiken som har skrivit sitt namn.
                    let people = session.peers.filter { $0.role == .editor }.map(\.name) + session.audienceNames
                    text = Array(NSOrderedSet(array: people)).compactMap { $0 as? String }.joined(separator: "\n")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func spin() {
        let o = Array(options.prefix(12))
        session.send(.wheel(options: o, winner: Int.random(in: 0..<o.count), nonce: UUID()))
        dismiss()
    }
}

struct QuestionSheet: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if session.live.questions.isEmpty {
                    ContentUnavailableView("Inga frågor än", systemImage: "questionmark.bubble",
                                           description: Text("Publiken kan skriva frågor på sidan de röstar på."))
                }
                ForEach(session.live.questions.reversed()) { q in
                    Button {
                        session.send(.showQuestion(session.live.shownQuestion == q ? nil : q))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(q.text).font(.body).foregroundStyle(.primary)
                            Text(session.live.shownQuestion == q ? "\(q.name) · visas nu på skärmen" : q.name)
                                .font(.caption).foregroundStyle(session.live.shownQuestion == q ? .green : .secondary)
                        }
                    }
                }
            }
            .navigationTitle("Frågor från publiken").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Klar") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}
