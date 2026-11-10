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
                                    Button("Ta bort", systemImage: "trash", role: .destructive) { toDelete = d }
                                }
                        }
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
            .sheet(isPresented: $choosingTheme) { ThemePicker { theme in
                choosingTheme = false
                model.open(model.library.create(theme: theme))
            } }
            .sheet(isPresented: $editingProfile) { ProfileEditor() }
            .confirmationDialog("Ta bort \(toDelete?.title ?? "")?", isPresented: .init(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Ta bort", role: .destructive) { if let d = toDelete { model.library.delete(d) }; toDelete = nil }
            }
        }
        .onAppear { model.browser.start(); model.tvs.start() }
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

struct ThemePicker: View {
    var onPick: (Theme) -> Void
    @Environment(\.dismiss) private var dismiss
    private let assets = AssetStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("theme-preview"))
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                    ForEach(Theme.all) { t in
                        Button { onPick(t) } label: {
                            VStack {
                                SlideView(slide: SlideLayout.title.makeSlide(theme: t), assets: assets)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Text(t.name).font(.headline)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Välj ett tema")
            .toolbar { Button("Avbryt") { dismiss() } }
        }
    }
}

struct ProfileEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var m = model
        NavigationStack {
            Form {
                TextField("Namn", text: $m.profile.name)
                ColorRow(selected: $m.profile.colorIndex).padding(.vertical, 8)
            }
            .navigationTitle("Du")
            .toolbar { Button("Klar") { dismiss() } }
        }
    }
}
