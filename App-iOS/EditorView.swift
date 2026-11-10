import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import SlideKit

struct EditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var hSize
    let session: Session

    @State private var currentSlide: UUID?
    @State private var selection: UUID?
    @State private var presenting = false
    @State private var showInspector = false
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var photo: PhotosPickerItem?
    @State private var showGiphy = false
    @State private var drawing = false
    @State private var showAI = false
    @State private var aiStartsInLibrary = false
    @State private var choosingSource = false
    @State private var pickingPhoto = false
    @State private var showCamera = false
    @State private var notice: String?
    @State private var practicing = false
    @State private var showBoard = false
    @State private var choosingScreen = false
    @State private var focusText = 0

    private var deck: Deck { session.deck }
    /// Är en bild markerad när man öppnar "Gör en bild" blir den referensbild ("gör om den här").
    private var selectedImageData: Data? {
        guard let id = selection, case .image(let box) = slide?.element(id)?.content else { return nil }
        return session.assets.data(box.assetID)
    }
    private var joinTitle: String { "\(session.joinRequests.first?.name ?? "Någon") vill bygga med dig" }
    private var slide: Slide? { currentSlide.flatMap { deck.slide($0) } ?? deck.slides.first }

    var body: some View {
        NavigationStack {
            Group {
                if hSize == .regular { wide } else { narrow }
            }
            .safeAreaInset(edge: .top) { StatusBanner(session: session) }
            .navigationTitle(deck.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .toolbarRole(.editor)
        }
        .fullScreenCover(isPresented: $presenting) { PresentView(session: session) }
        .fullScreenCover(isPresented: $practicing) {
            PracticeView(deck: deck, assets: session.assets, startAt: currentSlide.flatMap { deck.slideIndex($0) } ?? 0)
        }
        .sheet(isPresented: $showBoard) {
            BoardView(session: session, onSave: { png, frame in selection = nil; placeDrawing(png, frame) })
        }
        .onChange(of: session.live.board) { _, on in if on { showBoard = true } }
        .confirmationDialog("Var vill du visa presentationen?", isPresented: $choosingScreen, titleVisibility: .visible) {
            if session.role != .client {
                ForEach(model.tvs.hosts) { tv in
                    Button("\(tv.name) (Apple TV)") { presentOn(tv) }
                }
            }
            Button("Här på \(UIDevice.current.userInterfaceIdiom == .pad ? "iPaden" : "telefonen")") { startPresenting() }
            Button("Öva (visas inte för någon annan)") { selection = nil; practicing = true }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("På Apple TV blir din skärm fjärrkontroll och visar det som är dolt.")
        }
        .fullScreenCover(isPresented: $drawing) {
            if let s = slide { DrawSheet(slide: s, assets: session.assets) { png, frame in placeDrawing(png, frame) } }
        }
        .sheet(isPresented: $showAI) {
            AIImageSheet(startReference: selectedImageData, startInLibrary: aiStartsInLibrary) { data in placeImage(data) }
        }
        // Tryck på en bildplats: var ska bilden komma ifrån?
        .confirmationDialog("Lägg till en bild", isPresented: $choosingSource, titleVisibility: .visible) {
            Button("Klistra in") { pasteIntoPlaceholder() }
            Button("Gör en bild med AI") { aiStartsInLibrary = false; showAI = true }
            if ImageLibrary.containerID != nil {
                Button("Familjens bildbibliotek") { aiStartsInLibrary = true; showAI = true }
            }
            Button("Välj bland mina bilder") { pickingPhoto = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Ta ett foto") { showCamera = true }
            }
            Button("Avbryt", role: .cancel) {}
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
        .fullScreenCover(isPresented: $showCamera) { CameraPicker { data in placeImage(data) }.ignoresSafeArea() }
        .alert(notice ?? "", isPresented: .init(get: { notice != nil }, set: { if !$0 { notice = nil } })) { Button("OK") {} }
        .sheet(isPresented: $showGiphy) { GiphyPicker { data in placeImage(data) }.presentationSizing(.page) }
        .alert("Byt namn", isPresented: $renaming) {
            TextField("Namn", text: $newTitle)
            Button("Spara") { if !newTitle.isEmpty { session.perform(.setTitle(newTitle)) } }
            Button("Avbryt", role: .cancel) {}
        }
        .alert(joinTitle, isPresented: .init(get: { !session.joinRequests.isEmpty }, set: { _ in })) {
            if let p = session.joinRequests.first {
                Button("Släpp in") { session.answer(p.id, admit: true) }
                Button("Nej", role: .cancel) { session.answer(p.id, admit: false) }
            }
        } message: { Text("Då kan hen ändra i presentationen tillsammans med dig.") }
        .alert("Din delning avslutades", isPresented: .init(get: { model.takeover != nil }, set: { if !$0 { model.takeover = nil } })) {
            Button("OK") {}
        } message: { Text("»\(model.takeover ?? "")« började delas och tog över. Tryck Dela om du vill ta tillbaka TV:n.") }
        .alert("Du fick en presentation!", isPresented: .init(get: { model.gift != nil }, set: { if !$0 { model.gift = nil } })) {
            Button("OK") {}
        } message: { Text("»\(model.gift ?? "")« ligger nu bland dina presentationer.") }
        .onChange(of: selection) { _, new in session.select(new) }
        // Skärmen får inte somna medan man delar: då pausar iOS appen och TV:n tappar kontakten.
        .onChange(of: session.role, initial: true) { _, r in UIApplication.shared.isIdleTimerDisabled = r == .host }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: currentSlide) { _, new in session.setPresence(slide: new) }
        .onChange(of: deck) { _, d in
            // Bilden eller elementet kan ha försvunnit (ångra, någon annan tog bort det).
            if let c = currentSlide, d.slide(c) == nil { currentSlide = d.slides.first?.id }
            if let s = selection, slide?.element(s) == nil { selection = nil }
        }
        .onChange(of: photo) { _, item in Task { await addPhoto(item) } }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-giphy") { showGiphy = true }
            if ProcessInfo.processInfo.arguments.contains("-aiimage") { showAI = true }
            #endif
            currentSlide = deck.slides.first?.id
            #if DEBUG
            // -selectstar: markera stjärnan på bild 2 (för att se knappraden på simulatorn).
            if ProcessInfo.processInfo.arguments.contains("-selectstar"), deck.slides.count > 1,
               let star = deck.slides[1].elements.first(where: { if case .shape(let b) = $0.content { b.kind == .star } else { false } }) {
                currentSlide = deck.slides[1].id
                selection = star.id
            }
            #endif
            session.setPresence(slide: currentSlide)
            #if DEBUG
            // -extras: ett diagram med formatpanelen öppen (för simulatorn).
            if ProcessInfo.processInfo.arguments.contains("-extras") {
                if deck.slides.count > 2 { currentSlide = deck.slides[2].id }
                addChart(); addTimer(); addSticky()
                showInspector = true
            }
            // -placeholder: en bild med bildplats, markerad, med källmenyn öppen (för simulatorn).
            if ProcessInfo.processInfo.arguments.contains("-placeholder") {
                let s = SlideLayout.textAndPicture.makeSlide(theme: Theme.all[0])
                session.perform(.insertSlide(s, at: 1))
                currentSlide = s.id
                selection = s.elements.last?.id
                if ProcessInfo.processInfo.arguments.contains("-menu") { choosingSource = true }
            }
            // -presenter: börja presentera bild 2 efter en stund (för att se presentatörens skärm på simulatorn).
            if ProcessInfo.processInfo.arguments.contains("-presenter") {
                Task {
                    try? await Task.sleep(nanoseconds: 7_000_000_000)
                    if deck.slides.count > 1 { currentSlide = deck.slides[1].id }
                    startPresenting()
                }
            }
            #endif
        }
    }

    // MARK: Layout

    private var wide: some View {
        HStack(spacing: 0) {
            SlideList(session: session, current: $currentSlide, axis: .vertical)
                .frame(width: 200)
            Divider()
            canvas
            Divider()
            inspector.frame(width: 320)
        }
    }

    private var narrow: some View {
        VStack(spacing: 0) {
            canvas
                .overlay(alignment: .bottomTrailing) {
                    Button { play() } label: {
                        Label("Spela", systemImage: "play.fill").font(.headline)
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .foregroundStyle(.white).background(Color.green, in: Capsule())
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    }
                    .padding(14)
                }
            Divider()
            SlideList(session: session, current: $currentSlide, axis: .horizontal)
                .frame(height: 110)
        }
        .sheet(isPresented: $showInspector) {
            inspector.presentationDetents([.medium, .large]).presentationBackgroundInteraction(.enabled)
        }
    }

    private var canvas: some View {
        ZStack {
            Color(.secondarySystemBackground).ignoresSafeArea()
            if let s = slide {
                CanvasEditor(session: session, slide: s, selection: $selection, onPaste: { providers in
                    Task { await paste(providers) }
                }, onFormat: hSize == .regular ? nil : { showInspector = true },
                   onPlaceholder: { _ in choosingSource = true }) { _ in
                    focusText += 1
                    if hSize != .regular { showInspector = true }
                }
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                .padding(hSize == .regular ? 40 : 12)
            }
        }
    }

    @ViewBuilder private var inspector: some View {
        if let s = slide {
            Inspector(session: session, slide: s, selection: $selection, focusText: focusText)
        }
    }

    // MARK: Verktyg

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Klar") { model.close() }
        }
        ToolbarItemGroup(placement: .topBarLeading) {
            Button { session.undo() } label: { Label("Ångra", systemImage: "arrow.uturn.backward") }
                .disabled(!session.canUndo)
            Button { session.redo() } label: { Label("Gör om", systemImage: "arrow.uturn.forward") }
                .disabled(!session.canRedo)
        }
        ToolbarItemGroup(placement: .principal) {
            Button { newTitle = deck.title; renaming = true } label: {
                Text(deck.title).font(.headline).lineLimit(1)
            }
            .buttonStyle(.plain)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { addText() } label: { Label("Text", systemImage: "textformat") }
            Menu {
                ForEach(ShapeKind.allCases, id: \.self) { k in
                    Button(k.name, systemImage: k.symbol) { addShape(k) }
                }
            } label: { Label("Form", systemImage: "star.square.on.square") }
            PhotosPicker(selection: $photo, matching: .any(of: [.images, .videos])) { Label("Bild eller video", systemImage: "photo") }
            Button { showGiphy = true } label: { Label("GIF", systemImage: "sparkles") }
            Button { aiStartsInLibrary = false; showAI = true } label: { Label("Gör en bild med AI", systemImage: "wand.and.stars") }
            Button { addPlaceholder() } label: { Label("Bildplats", systemImage: "photo.badge.plus") }
            Button { addChart() } label: { Label("Diagram", systemImage: "chart.pie.fill") }
            Button { addSticky() } label: { Label("Lapp till de andra", systemImage: "note.text.badge.plus") }
            Button { selection = nil; drawing = true } label: { Label("Rita", systemImage: "pencil.tip.crop.circle") }
            Menu {
                Button("Omröstning", systemImage: "chart.bar.fill") { addPoll(quiz: false) }
                Button("Quizfråga", systemImage: "checkmark.seal.fill") { addPoll(quiz: true) }
                Button("Nedräkning", systemImage: "timer") { addTimer() }
            } label: { Label("Fråga publiken", systemImage: "chart.bar.fill") }
            PasteButton(supportedContentTypes: [.image, .plainText]) { providers in
                Task { await paste(providers) }
            }
            .labelStyle(.iconOnly)
            if hSize != .regular {
                Button { showInspector = true } label: { Label("Format", systemImage: "paintbrush") }
            }
            CollabMenu(session: session)
            ExportMenu(deck: deck, assets: session.assets)
        }
        // På iPhone hamnar verktygsradens knappar under ⋯; där ligger Spela i stället ovanpå bildytan.
        if hSize == .regular {
            ToolbarItem(placement: .confirmationAction) {
                Button { play() } label: { Label("Spela", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).tint(.green)
            }
        }
    }

    // MARK: Åtgärder

    private func place(_ e: Element) {
        guard let s = slide else { return }
        if session.perform(.upsertElement(slide: s.id, e, at: nil)) { selection = e.id }
    }

    /// Nya saker hamnar mitt på bilden, lite förskjutna så att de inte täcker varandra.
    private func centered(w: Double, h: Double) -> Frame {
        let n = Double((slide?.elements.count ?? 0) % 5) * 30
        return Frame(x: (SlideSize.width - w) / 2 + n, y: (SlideSize.height - h) / 2 + n, w: w, h: h)
    }

    private func addText(_ text: String? = nil) {
        guard let s = slide else { return }
        var style = Theme.inferred(from: s).body
        style.align = text == nil ? .center : .leading
        let lines = Double(max(text?.components(separatedBy: "\n").count ?? 1, 1))
        let h = min(lines * style.size * 1.3 + 20, 900)
        place(Element(frame: centered(w: text == nil ? 900 : 1400, h: h),
                      content: .text(TextBox(text: text ?? "Skriv här", style: style))))
        if text == nil { focusText += 1 }
    }

    private func addShape(_ k: ShapeKind) {
        guard let s = slide else { return }
        let side = k == .arrow ? (w: 500.0, h: 260.0) : (w: 360.0, h: 360.0)
        place(Element(frame: centered(w: side.w, h: side.h),
                      content: .shape(ShapeBox(kind: k, fill: Theme.inferred(from: s).accent))))
    }

    /// Publiken röstar med mobilen via QR-koden som dyker upp när man delar och presenterar.
    private func addPoll(quiz: Bool) {
        guard let s = slide else { return }
        let theme = Theme.inferred(from: s)
        let box = PollBox(question: quiz ? "Vilket är rätt?" : "Vad tycker ni?",
                          options: quiz ? ["Svar A", "Svar B", "Svar C"] : ["Ja", "Nej", "Kanske"],
                          correct: quiz ? 0 : nil, accent: theme.accent, textColor: theme.body.color)
        place(Element(frame: Frame(x: 210, y: 190, w: 1500, h: 700), content: .poll(box)))
    }

    /// En teckning blir en vanlig bild (genomskinlig PNG), så den följer med i exporten.
    private func placeDrawing(_ png: Data, _ frame: Frame) {
        guard let id = try? session.assets.importImage(png) else { return }
        place(Element(frame: frame, content: .image(ImageBox(assetID: id))))
    }

    private func addPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        photo = nil
        // Videoklipp komprimeras först (högst 20 sekunder), så att de går att skicka till de andra.
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let movie = try? await item.loadTransferable(type: MovieFile.self) else { return }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            guard let mp4 = await VideoImport.mp4(from: movie.url), let id = try? session.assets.importVideo(mp4) else {
                notice = "Det gick inte att lägga in klippet. Prova ett kortare."
                return
            }
            let (pw, ph) = session.assets.pixelSize(id) ?? (16, 9)
            let k = min(1100 / Double(pw), 700 / Double(ph))
            place(Element(frame: centered(w: Double(pw) * k, h: Double(ph) * k), content: .image(ImageBox(assetID: id))))
            return
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        placeImage(data)
    }

    private func addTimer() {
        guard let s = slide else { return }
        place(Element(frame: centered(w: 420, h: 420), content: .timer(TimerBox(seconds: 30, color: Theme.inferred(from: s).title.color))))
    }

    private func addChart() {
        guard let s = slide else { return }
        let theme = Theme.inferred(from: s)
        place(Element(frame: Frame(x: 360, y: 220, w: 1200, h: 700),
                      content: .chart(ChartBox(title: "Mitt diagram", labels: ["Ett", "Två", "Tre"], values: [3, 5, 2],
                                               accent: theme.accent, textColor: theme.body.color))))
    }

    /// En gul lapp som bara syns när man bygger: "byt den här bilden?".
    private func addSticky() {
        place(Element(frame: centered(w: 460, h: 300), rotation: -3,
                      content: .text(TextBox(text: "Skriv en lapp till de andra")), sticky: true, author: session.me.name))
        focusText += 1
        if hSize != .regular { showInspector = true }
    }

    /// En tom bildplats att fylla senare (eller låta någon annan fylla).
    private func addPlaceholder() {
        place(Element(frame: centered(w: 760, h: 520), content: .image(.placeholder)))
    }

    /// Urklippets bild hamnar i den markerade bildplatsen. (Att läsa urklippet härifrån kan ge iOS fråga
    /// "Tillåt inklistring"; knappen Klistra in i verktygsraden slipper den.)
    private func pasteIntoPlaceholder() {
        let pb = UIPasteboard.general
        if let gif = pb.data(forPasteboardType: UTType.gif.identifier) { return placeImage(gif) }
        if let img = pb.image, let data = img.pngData() { return placeImage(data) }
        notice = "Det finns ingen bild i urklippet. Kopiera en bild först, till exempel i Safari."
    }

    private func placeImage(_ data: Data) {
        guard let id = try? session.assets.importImage(data) else { return }
        let (pw, ph) = session.assets.pixelSize(id) ?? (4, 3)
        // Är en bildplats markerad hamnar bilden där, inpassad i platsens ruta.
        if let s = slide, let sel = selection, var e = s.element(sel), e.isImagePlaceholder {
            let f = e.frame
            let k = min(f.w / Double(pw), f.h / Double(ph))
            let w = Double(pw) * k, h = Double(ph) * k
            e.frame = Frame(x: f.x + (f.w - w) / 2, y: f.y + (f.h - h) / 2, w: w, h: h)
            e.content = .image(ImageBox(assetID: id))
            session.perform(.upsertElement(slide: s.id, e, at: nil))
            return
        }
        let scale = min(1100 / Double(pw), 800 / Double(ph))
        place(Element(frame: centered(w: Double(pw) * scale, h: Double(ph) * scale), content: .image(ImageBox(assetID: id))))
    }

    /// Klistra in från urklipp (t.ex. "Kopiera" på en bild i Safari): bilder blir bilder, text blir en textruta.
    /// Bilden har företräde, eftersom Safari ofta lägger både bilden och dess adress i urklippet.
    func paste(_ providers: [NSItemProvider]) async {
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.image.identifier),
               let data = await p.data(for: .image) {
                placeImage(data)
                return
            }
        }
        for p in providers where p.canLoadObject(ofClass: NSString.self) {
            if let text = await p.string(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                addText(text)
                return
            }
        }
    }

    /// Spela: finns det en Apple TV med Woop Woop öppen får man välja den. Annars presenterar vi här.
    private func play() {
        choosingScreen = true
    }

    /// Visa på en Apple TV: dela (om vi inte redan gör det), be just den TV:n ansluta och starta.
    /// TV:n får presentationsläget i välkomsten, så den visar presentationen direkt.
    private func presentOn(_ tv: HostBrowser.Host) {
        session.invite(tv: tv.endpoint)
        startPresenting()
    }

    private func startPresenting() {
        selection = nil
        let i = currentSlide.flatMap { deck.slideIndex($0) } ?? 0
        session.setPresent(PresentState(isPresenting: true, slideIndex: i))
        presenting = true
    }
}

extension Theme {
    /// Temat som en bild ser ut att ha, så att nya bilder och texter passar in.
    static func inferred(from slide: Slide) -> Theme {
        if let t = Theme.all.first(where: { $0.background == slide.background }) { return t }
        var t = Theme.all.last!
        t.background = slide.background
        let texts = slide.elements.compactMap { e -> TextStyle? in
            if case .text(let tb) = e.content { return tb.style }
            return nil
        }
        if let first = texts.first { t.title = first }
        if texts.count > 1 { t.body = texts[1] }
        return t
    }
}

/// Visar om vi delar, är anslutna eller har tappat kontakten, och om någon presenterar.
struct StatusBanner: View {
    let session: Session
    @State private var problem: String?
    var body: some View {
        VStack(spacing: 0) {
            switch session.link {
            case .connecting:
                banner(session.role == .host ? "Börjar dela…" : "Väntar på att värden släpper in dig…",
                       "antenna.radiowaves.left.and.right", .orange)
            case .lost(let why):
                banner(session.role == .solo && !session.turnedAway ? "\(why). Försöker igen…" : why, "wifi.slash", .red)
            case .connected:
                HStack(spacing: -8) {
                    ForEach(session.peers) { p in
                        Text(p.role == .stage ? "TV" : String(p.name.prefix(1)))
                            .font(.caption.bold()).foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(p.color.color, in: Circle())
                            .overlay { Circle().stroke(Color(.systemBackground), lineWidth: 2) }
                            .accessibilityLabel(p.name)
                    }
                    Text(session.role == .host ? "  Du delar" : "  Ni bygger tillsammans")
                        .font(.footnote).foregroundStyle(.secondary).padding(.leading, 12)
                    Spacer()
                    if session.present.isPresenting {
                        Label("Presenterar bild \(session.present.slideIndex + 1)", systemImage: "play.tv.fill")
                            .font(.footnote.bold()).foregroundStyle(.green)
                    }
                }
                .padding(.horizontal).padding(.vertical, 6)
                .background(.bar)
                if session.live.board {
                    Label("Ritytan är öppen – alla kan rita på TV:n", systemImage: "scribble.variable")
                        .font(.footnote.bold()).frame(maxWidth: .infinity).padding(.vertical, 6)
                        .foregroundStyle(.white).background(Color.purple)
                }
                if session.present.isPresenting {
                    // Publiken hejar: reaktionerna flyger upp över presentationen på TV:n.
                    HStack(spacing: 6) {
                        ForEach(LiveState.emoji.indices, id: \.self) { i in
                            Button { session.send(.reaction(i)) } label: {
                                Text(LiveState.emoji[i]).font(.title2).frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Skicka \(LiveState.emoji[i])")
                        }
                    }
                    .padding(.horizontal).padding(.bottom, 6)
                    .background(.bar)
                }
            case .none:
                // Inget delas förrän man själv trycker här.
                Button {
                    do { try session.startHosting() } catch { problem = "\(error)" }
                } label: {
                    Label("Dela – visa på TV:n och bygg tillsammans", systemImage: "person.2.wave.2.fill")
                        .font(.footnote.bold())
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal).padding(.vertical, 6)
                .background(.bar)
                if let problem { banner(problem, "exclamationmark.triangle", .red) }
            }
        }
    }

    private func banner(_ text: String, _ icon: String, _ color: Color) -> some View {
        Label(text, systemImage: icon).font(.footnote.bold()).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(8).background(color)
    }
}

struct CollabMenu: View {
    @Environment(AppModel.self) private var model
    let session: Session
    @State private var error: String?
    var body: some View {
        Menu {
            switch session.role {
            case .solo:
                Button("Dela", systemImage: "person.2.wave.2") {
                    do { try session.startHosting() } catch { self.error = "\(error)" }
                }
            case .host:
                Section("\(session.peers.count - 1) till är med") {
                    ForEach(session.peers.filter { $0.id != session.me.id }) { p in Text(p.name) }
                }
                Button(session.live.board ? "Stäng ritytan" : "Rita tillsammans på TV:n", systemImage: "scribble.variable") {
                    session.send(.board(!session.live.board))
                }
                let others = session.peers.filter { $0.id != session.me.id && $0.role == .editor }
                if !others.isEmpty {
                    Menu("Ge en kopia till …", systemImage: "gift") {
                        ForEach(others) { p in Button(p.name) { session.give(to: p.id) } }
                    }
                }
                Button("Sluta dela", systemImage: "xmark.circle", role: .destructive) { session.stopHosting() }
            case .client:
                if session.live.board {
                    Button("Stäng ritytan", systemImage: "scribble.variable") { session.send(.board(false)) }
                } else {
                    Button("Rita tillsammans på TV:n", systemImage: "scribble.variable") { session.send(.board(true)) }
                }
                Button("Spara en egen kopia", systemImage: "square.and.arrow.down") {
                    _ = model.library.saveCopy(of: session.deck)
                }
                Button("Lämna", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { model.close() }
            }
        } label: {
            Label("Tillsammans", systemImage: session.role == .solo ? "person.2" : "person.2.fill")
        }
        .alert("Kunde inte dela", isPresented: .init(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }
}
