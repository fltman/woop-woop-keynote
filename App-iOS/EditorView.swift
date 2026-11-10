import SwiftUI
import PhotosUI
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
    @State private var focusText = 0

    private var deck: Deck { session.deck }
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
            currentSlide = deck.slides.first?.id
            session.setPresence(slide: currentSlide)
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
                CanvasEditor(session: session, slide: s, selection: $selection) { _ in
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
            PhotosPicker(selection: $photo, matching: .images) { Label("Bild", systemImage: "photo") }
            if hSize != .regular {
                Button { showInspector = true } label: { Label("Format", systemImage: "paintbrush") }
            }
            CollabMenu(session: session)
            ExportMenu(deck: deck, assets: session.assets)
            Button { startPresenting() } label: { Label("Spela", systemImage: "play.fill") }
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

    private func addText() {
        guard let s = slide else { return }
        var style = Theme.inferred(from: s).body
        style.align = .center
        place(Element(frame: centered(w: 900, h: 160), content: .text(TextBox(text: "Skriv här", style: style))))
        focusText += 1
    }

    private func addShape(_ k: ShapeKind) {
        guard let s = slide else { return }
        let side = k == .arrow ? (w: 500.0, h: 260.0) : (w: 360.0, h: 360.0)
        place(Element(frame: centered(w: side.w, h: side.h),
                      content: .shape(ShapeBox(kind: k, fill: Theme.inferred(from: s).accent))))
    }

    private func addPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let id = try? session.assets.importImage(data) else { return }
        photo = nil
        let (pw, ph) = session.assets.pixelSize(id) ?? (4, 3)
        let scale = min(1100 / Double(pw), 800 / Double(ph))
        place(Element(frame: centered(w: Double(pw) * scale, h: Double(ph) * scale), content: .image(ImageBox(assetID: id))))
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
                banner(session.role == .solo ? "\(why). Försöker igen…" : why, "wifi.slash", .red)
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
                Button("Sluta dela", systemImage: "xmark.circle", role: .destructive) { session.stopHosting() }
            case .client:
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
