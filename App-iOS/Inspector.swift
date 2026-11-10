import SwiftUI
import PhotosUI
import SlideKit

extension RGBA {
    init(_ c: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Double(r), Double(g), Double(b), Double(a))
    }
}

/// Formatpanelen: elementet som är markerat, annars själva bilden.
struct Inspector: View {
    let session: Session
    let slide: Slide
    @Binding var selection: UUID?
    var focusText: Int

    var body: some View {
        Form {
            if let id = selection, let e = slide.element(id) {
                ElementInspector(session: session, slide: slide, element: e, focusText: focusText) { selection = nil }
            } else {
                SlideInspector(session: session, slide: slide)
            }
        }
        .formStyle(.grouped)
    }
}

struct ElementInspector: View {
    let session: Session
    let slide: Slide
    let element: Element
    var focusText: Int
    var onDeleted: () -> Void
    @FocusState private var textFocused: Bool
    @State private var rewriting = false
    @State private var rewriteProblem: String?

    /// Ändrar elementet som det ser ut JUST NU (inte som det såg ut när vyn ritades).
    private func update(_ key: String, _ change: (inout Element) -> Void) {
        guard var e = session.deck.slide(slide.id)?.element(element.id) else { return }
        change(&e)
        session.perform(.upsertElement(slide: slide.id, e, at: nil), coalesce: "\(element.id)-\(key)")
    }

    private func bind<T>(_ key: String, _ get: @escaping (Element) -> T, _ set: @escaping (inout Element, T) -> Void) -> Binding<T> {
        Binding(get: { get(element) }, set: { v in update(key) { set(&$0, v) } })
    }

    private func text<T>(_ key: String, _ kp: WritableKeyPath<TextBox, T>, _ fallback: T) -> Binding<T> {
        bind(key, { e in if case .text(let t) = e.content { t[keyPath: kp] } else { fallback } },
             { e, v in if case .text(var t) = e.content { t[keyPath: kp] = v; e.content = .text(t) } })
    }

    private func poll<T>(_ key: String, _ kp: WritableKeyPath<PollBox, T>, _ fallback: T) -> Binding<T> {
        bind(key, { e in if case .poll(let p) = e.content { p[keyPath: kp] } else { fallback } },
             { e, v in if case .poll(var p) = e.content { p[keyPath: kp] = v; e.content = .poll(p) } })
    }

    private func chart<T>(_ key: String, _ kp: WritableKeyPath<ChartBox, T>, _ fallback: T) -> Binding<T> {
        bind(key, { e in if case .chart(let c) = e.content { c[keyPath: kp] } else { fallback } },
             { e, v in if case .chart(var c) = e.content { c[keyPath: kp] = v; e.content = .chart(c) } })
    }

    /// Trollstaven: skriver om textrutans text. Det blir ett vanligt ångra-steg.
    private func rewrite(_ purpose: AIImage.Purpose, _ key: String) {
        guard case .text(let tb) = element.content, !tb.text.isEmpty else { return }
        rewriting = true; rewriteProblem = nil
        Task {
            defer { rewriting = false }
            do {
                let new = try await AIImage.refine(tb.text, purpose: purpose, key: key)
                update("ai-\(UUID())") { e in if case .text(var t) = e.content { t.text = new; e.content = .text(t) } }
            } catch let p as AIImage.Problem { rewriteProblem = p.localizedDescription }
            catch { rewriteProblem = "Ingen kontakt med tjänsten. Försök igen." }
        }
    }

    /// Klipper ut motivet på enheten och byter bilden mot den utklippta. Ångra tar tillbaka.
    private func removeBackground(_ box: ImageBox) {
        guard let data = session.assets.data(box.assetID) else { return }
        rewriting = true; rewriteProblem = nil
        Task {
            defer { rewriting = false }
            guard let cut = await BackgroundRemover.remove(data), let id = try? session.assets.importImage(cut),
                  let (pw, ph) = session.assets.pixelSize(id) else {
                rewriteProblem = "Hittade inget tydligt motiv att klippa ut."
                return
            }
            update("cut-\(UUID())") { e in
                // Det utklippta motivet är mindre än originalet: passa in det i samma ruta.
                let f = e.frame, k = min(f.w / Double(pw), f.h / Double(ph))
                e.frame = Frame(x: f.midX - Double(pw) * k / 2, y: f.midY - Double(ph) * k / 2, w: Double(pw) * k, h: Double(ph) * k)
                e.content = .image(ImageBox(assetID: id))
            }
        }
    }

    private func shape<T>(_ key: String, _ kp: WritableKeyPath<ShapeBox, T>, _ fallback: T) -> Binding<T> {
        bind(key, { e in if case .shape(let s) = e.content { s[keyPath: kp] } else { fallback } },
             { e, v in if case .shape(var s) = e.content { s[keyPath: kp] = v; e.content = .shape(s) } })
    }

    private func color(_ b: Binding<RGBA>) -> Binding<Color> {
        Binding(get: { b.wrappedValue.color }, set: { b.wrappedValue = RGBA($0) })
    }

    var body: some View {
        switch element.content {
        case .text:
            Section("Text") {
                TextField("Text", text: text("text", \.text, ""), axis: .vertical)
                    .lineLimit(2...10)
                    .focused($textFocused)
                Picker("Typsnitt", selection: text("font", \.style.font, .arial)) {
                    ForEach(FontFamily.allCases, id: \.self) { f in Text(f.rawValue).font(.custom(f.rawValue, size: 17)).tag(f) }
                }
                LabeledContent("Storlek") {
                    Slider(value: text("size", \.style.size, 64), in: 24...400)
                    Text("\(Int(text("size", \.style.size, 64).wrappedValue / 2))").monospacedDigit().frame(width: 40)
                }
                ColorPicker("Färg", selection: color(text("color", \.style.color, .black)))
                HStack {
                    Toggle(isOn: text("bold", \.style.bold, false)) { Image(systemName: "bold") }
                    Toggle(isOn: text("italic", \.style.italic, false)) { Image(systemName: "italic") }
                }
                .toggleStyle(.button)
                Picker("Justering", selection: text("align", \.style.align, .leading)) {
                    Image(systemName: "text.alignleft").tag(TextAlign.leading)
                    Image(systemName: "text.aligncenter").tag(TextAlign.center)
                    Image(systemName: "text.alignright").tag(TextAlign.trailing)
                }
                .pickerStyle(.segmented)
                if let key = AIImage.apiKey {
                    // Trollstaven för text: skriver om det som står i rutan. Ångra tar tillbaka.
                    Menu {
                        Button("Gör om till punkter", systemImage: "list.bullet") { rewrite(.bullets, key) }
                        Button("Gör kortare", systemImage: "arrow.down.right.and.arrow.up.left") { rewrite(.shorter, key) }
                        Button("Rätta stavningen", systemImage: "checkmark.circle") { rewrite(.spelling, key) }
                        Button("Föreslå en rubrik", systemImage: "textformat.size") { rewrite(.headline, key) }
                    } label: {
                        Label(rewriting ? "Skriver om …" : "Hjälp med texten", systemImage: "wand.and.stars")
                    }
                    .disabled(rewriting)
                    if let rewriteProblem { Text(rewriteProblem).font(.footnote).foregroundStyle(.red) }
                }
            }
            .onChange(of: focusText, initial: true) { _, n in if n > 0 { textFocused = true } }
        case .shape:
            Section("Form") {
                Picker("Form", selection: shape("kind", \.kind, .rectangle)) {
                    ForEach(ShapeKind.allCases, id: \.self) { k in Label(k.name, systemImage: k.symbol).tag(k) }
                }
                ColorPicker("Fyllning", selection: color(shape("fill", \.fill, .black)))
                Toggle("Kant", isOn: bind("stroke", { e in if case .shape(let s) = e.content { s.stroke != nil && s.strokeWidth > 0 } else { false } },
                                          { e, on in if case .shape(var s) = e.content { s.stroke = on ? .black : nil; s.strokeWidth = on ? 12 : 0; e.content = .shape(s) } }))
                if case .shape(let s) = element.content, s.stroke != nil {
                    ColorPicker("Kantfärg", selection: color(shape("strokeColor", \.stroke, nil).unwrapped(.black)))
                    Slider(value: shape("strokeWidth", \.strokeWidth, 0), in: 2...60) { Text("Kantbredd") }
                }
            }
        case .image(let box):
            if !box.isPlaceholder && !box.isVideo && !box.assetID.hasSuffix(".gif") {
                Section("Bild") {
                    Button { removeBackground(box) } label: {
                        Label(rewriting ? "Tar bort bakgrunden …" : "Ta bort bakgrunden", systemImage: "person.and.background.dotted")
                    }
                    .disabled(rewriting)
                    if let rewriteProblem { Text(rewriteProblem).font(.footnote).foregroundStyle(.red) }
                }
            }
        case .timer(let t):
            Section("Nedräkning") {
                Stepper("Tid: \(TimerBox.label(t.seconds))", value: bind("seconds", { e in
                    if case .timer(let t) = e.content { t.seconds } else { 30 }
                }, { e, v in if case .timer(var t) = e.content { t.seconds = v; e.content = .timer(t) } }), in: 5...600, step: 5)
                ColorPicker("Färg", selection: color(bind("tcolor", { e in
                    if case .timer(let t) = e.content { t.color } else { .white }
                }, { e, v in if case .timer(var t) = e.content { t.color = v; e.content = .timer(t) } })))
                Text("Tryck på klockan när du presenterar för att starta den. Ett tryck till nollställer.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .chart(let c):
            Section("Diagram") {
                Picker("Sort", selection: chart("kind", \.kind, .bar)) {
                    Text("Staplar").tag(ChartBox.Kind.bar)
                    Text("Cirkel").tag(ChartBox.Kind.pie)
                }
                .pickerStyle(.segmented)
                TextField("Rubrik", text: chart("title", \.title, ""))
                ForEach(c.labels.indices, id: \.self) { i in
                    HStack {
                        TextField("Namn", text: bind("cl\(i)", { e in
                            if case .chart(let c) = e.content, c.labels.indices.contains(i) { c.labels[i] } else { "" }
                        }, { e, v in if case .chart(var c) = e.content, c.labels.indices.contains(i) { c.labels[i] = v; e.content = .chart(c) } }))
                        TextField("Värde", value: bind("cv\(i)", { e in
                            if case .chart(let c) = e.content, c.values.indices.contains(i) { c.values[i] } else { 0.0 }
                        }, { e, v in if case .chart(var c) = e.content, c.values.indices.contains(i) { c.values[i] = v; e.content = .chart(c) } }),
                                  format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                        if c.labels.count > 2 {
                            Button("Ta bort raden", systemImage: "minus.circle") {
                                update("crm") { e in
                                    guard case .chart(var c) = e.content, c.labels.indices.contains(i), c.values.indices.contains(i) else { return }
                                    c.labels.remove(at: i); c.values.remove(at: i); e.content = .chart(c)
                                }
                            }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.red)
                        }
                    }
                }
                if c.labels.count < 8 {
                    Button("Lägg till rad", systemImage: "plus") {
                        update("cadd") { e in
                            guard case .chart(var c) = e.content else { return }
                            c.labels.append("Ny"); c.values.append(1); e.content = .chart(c)
                        }
                    }
                }
                ColorPicker("Första färgen", selection: color(chart("accent", \.accent, .black)))
                ColorPicker("Text", selection: color(chart("ctext", \.textColor, .white)))
            }
        case .poll(let p):
            Section(p.correct == nil ? "Omröstning" : "Quiz") {
                TextField("Fråga", text: poll("question", \.question, ""), axis: .vertical)
                    .lineLimit(1...3)
                    .focused($textFocused)
                ForEach(p.options.indices, id: \.self) { i in
                    HStack {
                        TextField("Alternativ \(i + 1)", text: bind("opt\(i)", { e in
                            if case .poll(let p) = e.content, p.options.indices.contains(i) { p.options[i] } else { "" }
                        }, { e, v in
                            if case .poll(var p) = e.content, p.options.indices.contains(i) { p.options[i] = v; e.content = .poll(p) }
                        }))
                        if p.options.count > 2 {
                            Button("Ta bort alternativet", systemImage: "minus.circle") {
                                update("optrm") { e in
                                    guard case .poll(var p) = e.content, p.options.indices.contains(i) else { return }
                                    p.options.remove(at: i)
                                    if let c = p.correct { p.correct = c == i ? nil : (c > i ? c - 1 : c) }
                                    e.content = .poll(p)
                                }
                            }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.red)
                        }
                    }
                }
                if p.options.count < 6 {
                    Button("Lägg till alternativ", systemImage: "plus") {
                        update("optadd") { e in
                            guard case .poll(var p) = e.content else { return }
                            p.options.append("Alternativ \(p.options.count + 1)"); e.content = .poll(p)
                        }
                    }
                }
                Picker("Rätt svar", selection: poll("correct", \.correct, nil)) {
                    Text("Inget (omröstning)").tag(Int?.none)
                    ForEach(p.options.indices, id: \.self) { i in Text(p.options[i]).tag(Int?.some(i)) }
                }
                ColorPicker("Staplar", selection: color(poll("accent", \.accent, .black)))
                ColorPicker("Text", selection: color(poll("textColor", \.textColor, .white)))
                Text("Publiken röstar med mobilen: tryck Dela och presentera, så dyker en QR-kod upp i rutan. I ett quiz trycker du på rutan för att visa rätt svar.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .onChange(of: focusText, initial: true) { _, n in if n > 0 { textFocused = true } }
        }

        Section("När du presenterar") {
            Picker("Visas", selection: bind("reveal", \.reveal, { $0.reveal = $1 })) {
                Text("Direkt").tag(AppearEffect?.none)
                ForEach(AppearEffect.allCases, id: \.self) { fx in
                    Text("När jag trycker – \(fx.name.lowercased())").tag(AppearEffect?.some(fx))
                }
            }
            Toggle("Försvinner när jag trycker", isOn: bind("vanish", \.vanishes, { $0.vanish = $1 ? true : nil }))
            Picker("Rör sig", selection: bind("motion", \.motion, { $0.motion = $1 })) {
                Text("Står still").tag(Motion?.none)
                ForEach(Motion.allCases, id: \.self) { m in Text(m.name).tag(Motion?.some(m)) }
            }
            SoundControls(session: session, slideID: slide.id, element: element)
        }

        Section("Placering") {
            LabeledContent("Vinkel") {
                Slider(value: bind("rotation", \.rotation, { $0.rotation = $1 }), in: -180...180)
                Text("\(Int(element.rotation))°").monospacedDigit().frame(width: 48)
            }
            HStack {
                Button("Längst fram", systemImage: "square.3.layers.3d.top.filled") { layer(to: Int.max) }
                Spacer()
                Button("Längst bak", systemImage: "square.3.layers.3d.bottom.filled") { layer(to: 0) }
            }
            .buttonStyle(.borderless)
        }

        Section("När man trycker") {
            Picker("Länk", selection: bind("link", \.link, { $0.link = $1 })) {
                Text("Ingenting").tag(ElementLink?.none)
                Text("Nästa bild").tag(ElementLink?.some(.nextSlide))
                Text("Förra bilden").tag(ElementLink?.some(.previousSlide))
                ForEach(Array(session.deck.slides.enumerated()), id: \.element.id) { i, s in
                    Text("Gå till bild \(i + 1)").tag(ElementLink?.some(.slide(s.id)))
                }
            }
        }

        Section {
            Button("Duplicera", systemImage: "plus.square.on.square") {
                var copy = element
                copy.id = UUID()
                copy.frame.x += 40; copy.frame.y += 40
                session.perform(.upsertElement(slide: slide.id, copy, at: nil))
            }
            Button("Ta bort", systemImage: "trash", role: .destructive) {
                session.perform(.deleteElement(slide: slide.id, element: element.id))
                onDeleted()
            }
        }
    }

    private func layer(to i: Int) {
        let n = slide.elements.count - 1
        session.perform(.moveElement(slide: slide.id, element: element.id, to: min(i, n)))
    }
}

extension Binding where Value == RGBA? {
    func unwrapped(_ fallback: RGBA) -> Binding<RGBA> {
        Binding<RGBA>(get: { wrappedValue ?? fallback }, set: { wrappedValue = $0 })
    }
}

struct SlideInspector: View {
    let session: Session
    let slide: Slide
    @State private var photo: PhotosPickerItem?
    @State private var makingBackground = false

    private func set(_ key: String, bg: Fill? = nil, notes: String? = nil, transition: DeckTransition? = nil) {
        guard let s = session.deck.slide(slide.id) else { return }
        session.perform(.setSlideProps(s.id, background: bg ?? s.background, notes: notes ?? s.notes,
                                       transition: transition ?? s.transition), coalesce: "\(s.id)-\(key)")
    }

    private enum BGKind: String, CaseIterable { case solid = "Färg", gradient = "Toning", image = "Bild" }
    private var kind: BGKind {
        switch slide.background { case .solid: .solid; case .gradient: .gradient; case .image: .image }
    }

    var body: some View {
        Section("Tema") {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(Theme.all) { t in
                        FillView(fill: t.background, assets: session.assets)
                            .frame(width: 64, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
                            .onTapGesture { set("theme", bg: t.background) }
                            .accessibilityLabel(t.name).accessibilityAddTraits(.isButton)
                    }
                }
            }
        }
        Section("Bakgrund") {
            Picker("Bakgrund", selection: Binding(get: { kind }, set: { k in
                switch k {
                case .solid: set("bgkind", bg: .solid(.white))
                case .gradient: set("bgkind", bg: .gradient(from: RGBA(hex: "1B1464"), to: RGBA(hex: "6F1E51"), angle: 90))
                case .image: break
                }
            })) {
                ForEach(BGKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            switch slide.background {
            case .solid(let c):
                ColorPicker("Färg", selection: Binding(get: { c.color }, set: { set("bg", bg: .solid(RGBA($0))) }))
            case .gradient(let a, let b, let ang):
                ColorPicker("Från", selection: Binding(get: { a.color }, set: { set("bg", bg: .gradient(from: RGBA($0), to: b, angle: ang)) }))
                ColorPicker("Till", selection: Binding(get: { b.color }, set: { set("bg", bg: .gradient(from: a, to: RGBA($0), angle: ang)) }))
                LabeledContent("Riktning") {
                    Slider(value: Binding(get: { ang }, set: { set("bg", bg: .gradient(from: a, to: b, angle: $0)) }), in: 0...360)
                }
            case .image:
                EmptyView()
            }
            PhotosPicker(selection: $photo, matching: .images) { Label("Välj en bild som bakgrund", systemImage: "photo") }
            if AIImage.apiKey != nil {
                Button { makingBackground = true } label: { Label("Gör en bakgrund med AI", systemImage: "wand.and.stars") }
                    .sheet(isPresented: $makingBackground) {
                        AIImageSheet(fixedShape: .wide) { data in
                            if let id = try? session.assets.importImage(data) { set("bgimage", bg: .image(assetID: id)) }
                        }
                    }
            }
        }
        Section("Övergång till den här bilden") {
            Picker("Övergång", selection: Binding(get: { slide.transition }, set: { set("tr", transition: $0) })) {
                ForEach(DeckTransition.allCases, id: \.self) { t in Text(t.name).tag(t) }
            }
        }
        Section("Anteckningar (syns bara för dig)") {
            TextField("Vad ska du säga?", text: Binding(get: { slide.notes }, set: { set("notes", notes: $0) }), axis: .vertical)
                .lineLimit(3...10)
        }
        .onChange(of: photo) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self),
                      let id = try? session.assets.importImage(data) else { return }
                photo = nil
                set("bgimage", bg: .image(assetID: id))
            }
        }
    }
}
