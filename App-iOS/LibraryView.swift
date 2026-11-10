import SwiftUI
import SlideKit

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var choosingTheme = false
    @State private var editingProfile = false
    @State private var toDelete: Deck?

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 20)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !model.browser.hosts.isEmpty {
                        Text("Bygg tillsammans").font(.title2.bold())
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(model.browser.hosts) { h in
                                Button { model.join(h) } label: {
                                    Label(h.name, systemImage: "person.2.wave.2.fill")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity, minHeight: 64)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    Text("Mina presentationer").font(.title2.bold())
                    LazyVGrid(columns: columns, spacing: 20) {
                        Button { choosingTheme = true } label: {
                            RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [10]))
                                .aspectRatio(16 / 9, contentMode: .fit)
                                .overlay { Label("Ny", systemImage: "plus").font(.title2.bold()) }
                        }
                        .buttonStyle(.plain)
                        ForEach(model.library.decks) { d in
                            Button { model.open(d) } label: { DeckCard(deck: d, assets: model.library.assets) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Duplicera", systemImage: "plus.square.on.square") { _ = model.library.saveCopy(of: d) }
                                    Button("Ta bort", systemImage: "trash", role: .destructive) { toDelete = d }
                                }
                        }
                    }
                    // Presentationer som finns i min iCloud men inte på den här enheten (ny telefon, eller borttagna här).
                    let onlyInCloud = model.backup.cloud.filter { c in !model.library.decks.contains { $0.id == c.id } }
                    if !onlyInCloud.isEmpty {
                        Text("I iCloud").font(.title2.bold())
                        ForEach(onlyInCloud) { c in
                            Button {
                                Task { if let d = await model.backup.restore(c) { model.library.add(d) } }
                            } label: {
                                HStack {
                                    Image(systemName: "icloud.and.arrow.down").font(.title2)
                                    VStack(alignment: .leading) {
                                        Text(c.title).font(.headline)
                                        Text(c.modified.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if model.backup.restoring == c.id { ProgressView() }
                                }
                                .padding(14).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Ta bort ur iCloud", systemImage: "trash", role: .destructive) { model.backup.delete(c.id) }
                            }
                        }
                    }
                    if let p = model.backup.problem {
                        Label(p, systemImage: "exclamationmark.icloud").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Woop Woop")
            .toolbar {
                Button { editingProfile = true } label: {
                    Label(model.profile.name, systemImage: "person.crop.circle.fill")
                        .foregroundStyle(model.profile.peer.color.color)
                }
            }
            .sheet(isPresented: $choosingTheme) { ThemePicker(onDraft: { deck in
                choosingTheme = false
                model.library.add(deck)
                model.open(deck)
            }) { theme, template in
                choosingTheme = false
                model.open(model.library.create(theme: theme, template: template))
            } }
            .task { await model.backup.refresh() }
            .sheet(isPresented: $editingProfile) { ProfileEditor() }
            .confirmationDialog("Ta bort \(toDelete?.title ?? "")?", isPresented: .init(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Ta bort", role: .destructive) { if let d = toDelete { model.library.delete(d) }; toDelete = nil }
            }
        }
        .onAppear {
            model.browser.start(); model.tvs.start()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-profile") { editingProfile = true }
            if ProcessInfo.processInfo.arguments.contains("-newdeck") { choosingTheme = true }
            #endif
        }
    }
}

struct DeckCard: View {
    var deck: Deck
    var assets: AssetStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let s = deck.slides.first { SlideView(slide: s, assets: assets) } else { Color.gray.opacity(0.2) }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 4, y: 2)
            Text(deck.title).font(.headline).lineLimit(1)
            Text("\(deck.slides.count) bilder · \(deck.modified.formatted(.relative(presentation: .named)))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Ny presentation: välj ett upplägg (färdiga bilder att fylla i) och sedan ett tema (färger och typsnitt).
struct ThemePicker: View {
    /// Ett AI-utkast är klart.
    var onDraft: (Deck) -> Void = { _ in }
    var onPick: (Theme, DeckTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var template = DeckTemplate.empty
    @State private var topic = ""
    @State private var drafting = false
    @State private var problem: String?

    /// Med ett ämne ifyllt gör AI ett utkast i temat man väljer. Annars används upplägget.
    private func choose(_ theme: Theme) {
        let t = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2, let key = AIImage.apiKey else { return onPick(theme, template) }
        drafting = true; problem = nil
        Task {
            defer { drafting = false }
            do { onDraft(try await AIDraft.make(topic: t, theme: theme, key: key)) }
            catch let p as AIImage.Problem { problem = p.localizedDescription }
            catch { problem = "Ingen kontakt med tjänsten. Försök igen, eller töm ämnesfältet." }
        }
    }
    private let assets = AssetStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("theme-preview"))
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("1. Välj upplägg").font(.headline).padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(DeckTemplate.allCases) { t in
                                Button { template = t } label: {
                                    Label(t.name, systemImage: t.symbol).font(.subheadline.bold())
                                        .padding(.horizontal, 14).padding(.vertical, 10)
                                        .foregroundStyle(t == template ? Color.white : Color.primary)
                                        .background(t == template ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(t == template ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal)
                    }
                    if AIImage.apiKey != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Eller: låt AI göra ett utkast").font(.headline)
                            TextField("Skriv ett ämne, till exempel vulkaner", text: $topic)
                                .padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            Text("Ämnet skickas till en texttjänst på internet. Du får några bilder med text att ändra och bildplatser att fylla i. Kontrollera fakta själv.")
                                .font(.caption).foregroundStyle(.secondary)
                            if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
                        }
                        .padding(.horizontal)
                    }
                    Text(drafting ? "Skriver utkastet …" : "2. Välj tema").font(.headline).padding(.horizontal).padding(.top, 6)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 16) {
                        ForEach(Theme.all) { t in
                            Button { choose(t) } label: {
                                VStack(spacing: 6) {
                                    // Förhandsvisningen är upplägget i det temat (andra bilden säger mer än rubriken).
                                    SlideView(slide: preview(t), assets: assets)
                                        .environment(\.liveState, LiveState())
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(.gray.opacity(0.3), lineWidth: 1) }
                                    Text(t.name).font(.subheadline.bold())
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .disabled(drafting).opacity(drafting ? 0.5 : 1)
                }
                .padding(.vertical)
            }
            .navigationTitle("Ny presentation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Avbryt") { dismiss() } }
        }
    }

    private func preview(_ t: Theme) -> Slide {
        let d = template.makeDeck(theme: t)
        return d.slides.first ?? SlideLayout.title.makeSlide(theme: t)
    }
}

struct ProfileEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var m = model
        NavigationStack {
            ScrollView {
                ProfileCard(name: $m.profile.name, colorIndex: $m.profile.colorIndex)
                    .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Det här är du")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Klar") { dismiss() }.bold()
                    .disabled(model.profile.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .interactiveDismissDisabled(model.profile.name.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}

/// Namn och färg, med en förhandsvisning av hur man syns för de andra och på TV:n.
struct ProfileCard: View {
    @Binding var name: String
    @Binding var colorIndex: Int
    @FocusState private var typing: Bool

    private var color: Color { Peer.palette[colorIndex % Peer.palette.count].color }
    private var shown: String { name.trimmingCharacters(in: .whitespaces).isEmpty ? "Du" : name.trimmingCharacters(in: .whitespaces) }
    private static let colorNames = ["Röd", "Blå", "Grön", "Orange", "Lila", "Rosa", "Turkos"]

    var body: some View {
        VStack(spacing: 22) {
            // Stor rund bricka med första bokstaven, som på TV:n och i listan över vilka som är med.
            Text(String(shown.prefix(1)).uppercased())
                .font(.system(size: 64, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .frame(width: 128, height: 128)
                .background(color.gradient, in: Circle())
                .shadow(color: color.opacity(0.5), radius: 16, y: 6)
                .animation(.spring(duration: 0.4, bounce: 0.5), value: colorIndex)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Vad heter du?").font(.subheadline.bold()).foregroundStyle(.secondary)
                TextField("Ditt namn", text: $name)
                    .font(.title2.bold())
                    .textInputAutocapitalization(.words).autocorrectionDisabled()
                    .submitLabel(.done).focused($typing)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(typing ? color : .clear, lineWidth: 2) }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Välj din färg").font(.subheadline.bold()).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    ForEach(Peer.palette.indices, id: \.self) { i in
                        Button { colorIndex = i } label: {
                            Circle().fill(Peer.palette[i].color.gradient)
                                .frame(width: 38, height: 38)
                                .overlay { if i == colorIndex { Image(systemName: "checkmark").font(.headline.bold()).foregroundStyle(.white) } }
                                .padding(4)
                                .overlay { if i == colorIndex { Circle().stroke(Peer.palette[i].color, lineWidth: 3) } }
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Self.colorNames[i % Self.colorNames.count])
                        .accessibilityAddTraits(i == colorIndex ? .isSelected : [])
                    }
                }
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Så syns du för de andra").font(.subheadline.bold()).foregroundStyle(.secondary)
                // En liten bild där "du" har markerat en ruta, precis som i redigeraren och på TV:n.
                ZStack {
                    LinearGradient(colors: [Color(red: 0.11, green: 0.08, blue: 0.39), Color(red: 0.44, green: 0.12, blue: 0.32)],
                                   startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.9)).frame(width: 150, height: 14)
                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.5)).frame(width: 100, height: 8)
                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.5)).frame(width: 120, height: 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 22)
                    Image(systemName: "star.fill").font(.system(size: 44)).foregroundStyle(Color(red: 1, green: 0.76, blue: 0.07))
                        .padding(10)
                        .overlay { RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 3) }
                        .overlay(alignment: .topLeading) {
                            Text(shown).font(.caption.bold()).foregroundStyle(.white).lineLimit(1)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(color, in: Capsule()).fixedSize()
                                .offset(x: -4, y: -24)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 44).padding(.top, 14)
                }
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .animation(.easeInOut(duration: 0.25), value: colorIndex)
                .accessibilityLabel("Förhandsvisning: det du markerar får en ram i din färg med ditt namn")
            }
        }
    }
}
