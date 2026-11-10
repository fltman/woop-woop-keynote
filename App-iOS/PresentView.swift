import SwiftUI
import SlideKit

/// Presentation på telefonen eller iPaden.
/// Utan Apple TV är den här skärmen själva presentationen (helskärm, kan speglas med AirPlay).
/// Med Apple TV blir den presentatörens skärm: nästa bild, klocka, anteckningar och fjärrkontroll.
struct PresentView: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var chrome = true
    /// nil = automatiskt: anteckningarna syns när en TV visar presentationen (då är den här skärmen
    /// bara min), men inte annars, eftersom skärmen då kan vara speglad till publiken.
    @State private var notesChoice: Bool?
    @State private var tool: LiveTool?
    @State private var started = Date()

    private var index: Int { session.present.slideIndex }
    private var hasStage: Bool { session.peers.contains { $0.role == .stage } }
    private var notes: String { session.deck.slides.indices.contains(index) ? session.deck.slides[index].notes : "" }
    private var showNotes: Bool { notesChoice ?? hasStage }

    var body: some View {
        Group {
            if hasStage { presenter } else { fullScreen }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: session.present.isPresenting) { _, on in if !on { dismiss() } }
    }

    // Dolda element syns som spöken här (bara för den som presenterar). Ljudet spelas av
    // presentationsskärmen: TV:n om den är med, annars den här enheten.
    private var slides: some View {
        PresentationView(deck: session.deck, state: session.present, assets: session.assets,
                         assetVersion: session.assetVersion, presenter: true,
                         playsSound: !hasStage, onTapElement: tap,
                         live: session.live, tool: tool, inkColor: session.me.color,
                         onLive: { session.send($0) })
    }

    // MARK: Helskärm (ingen TV)

    private var fullScreen: some View {
        slides
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                if v.translation.width < -40 { session.remote(.next) } else if v.translation.width > 40 { session.remote(.previous) }
            })
            .onTapGesture(coordinateSpace: .global) { p in
                // Höger del = nästa steg (dolt element eller nästa bild), vänster = förra bilden.
                let w = UIScreen.main.bounds.width
                session.remote(p.x > w * 0.3 ? .next : .previous)
                chrome = false
            }
            .overlay(alignment: .topLeading) {
                HStack {
                    closeButton
                    counter
                    if !notes.isEmpty {
                        round(showNotes ? "note.text" : "note", on: showNotes, label: showNotes ? "Göm anteckningarna" : "Visa anteckningarna") {
                            notesChoice = !showNotes
                        }
                    }
                    tools
                }
                .padding()
                .opacity(chrome || tool != nil ? 1 : 0.15)
            }
            .overlay(alignment: .bottom) {
                if showNotes && !notes.isEmpty {
                    Text(notes).font(.body).padding().frame(maxWidth: 700)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding()
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: Presentatörens skärm (TV:n visar presentationen)

    private var presenter: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if wide {
                    HStack(spacing: 16) {
                        VStack(spacing: 12) { current; controls }
                        VStack(spacing: 12) { topRow; nextPreview; notesBox }.frame(width: geo.size.width * 0.3)
                    }
                    .padding(12)
                } else {
                    VStack(spacing: 12) {
                        topRow
                        current
                        HStack(alignment: .top, spacing: 12) { nextPreview.frame(width: geo.size.width * 0.4); notesBox }
                        controls
                    }
                    .padding(12)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var current: some View {
        slides
            .aspectRatio(SlideSize.width / SlideSize.height, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .onTapGesture { session.remote(.next) }
    }

    private var topRow: some View {
        HStack {
            closeButton
            counter
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let s = Int(ctx.date.timeIntervalSince(started))
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%d:%02d", s / 60, s % 60)).font(.title2.monospacedDigit().bold())
                    Text(ctx.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
                .onTapGesture { started = Date() }
                .accessibilityLabel("Tid sedan start. Tryck för att nollställa.")
            }
        }
    }

    @ViewBuilder private var nextPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nästa").font(.caption.bold()).foregroundStyle(.secondary)
            if let next = session.deck.slides[safe: index + 1] {
                SlideView(slide: next, assets: session.assets, assetVersion: session.assetVersion)
                    .environment(\.animatesImages, false)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08))
                    .aspectRatio(SlideSize.width / SlideSize.height, contentMode: .fit)
                    .overlay { Text("Slut").font(.headline).foregroundStyle(.secondary) }
            }
        }
    }

    private var notesBox: some View {
        ScrollView {
            Text(notes.isEmpty ? "Inga anteckningar till den här bilden." : notes)
                .font(.title3).foregroundStyle(notes.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { session.remote(.previous) } label: {
                Image(systemName: "chevron.left").font(.title2.bold()).frame(width: 56, height: 56)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel("Förra bilden")
            tools
            Spacer(minLength: 0)
            Button { session.remote(.next) } label: {
                Label("Nästa", systemImage: "chevron.right").font(.title3.bold())
                    .frame(maxWidth: 220, minHeight: 56)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: Delar

    private var closeButton: some View {
        round("xmark", on: false, label: "Sluta presentera") { stop() }
    }

    private var counter: some View {
        Text("\(index + 1) / \(session.deck.slides.count)")
            .font(.headline.monospacedDigit()).padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
    }

    /// Laserpekare, penna, sudda och ljudknappar.
    @ViewBuilder private var tools: some View {
        round("dot.circle.and.hand.point.up.left.fill", on: tool == .laser, label: "Laserpekare") {
            tool = tool == .laser ? nil : .laser
            session.send(.pointer(nil))
        }
        round("pencil.tip", on: tool == .pen, label: "Rita på bilden") { tool = tool == .pen ? nil : .pen }
        if !session.live.ink.isEmpty {
            round("eraser.fill", on: false, label: "Sudda allt") { session.send(.clearInk) }
        }
        Menu {
            ForEach(Jingle.allCases, id: \.self) { j in
                Button("\(j.emoji)  \(j.name)") { session.send(.jingle(j, nonce: UUID())) }
            }
        } label: {
            Image(systemName: "speaker.wave.3.fill").font(.title3.bold()).frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Ljudknappar")
    }

    private func round(_ symbol: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title3.bold()).frame(width: 46, height: 46)
                .foregroundStyle(on ? Color.black : Color.primary)
                .background(on ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Dolt → visa (och spela dess ljud). Försvinner vid tryck → bort eller tillbaka.
    /// Quiz → visa eller göm rätt svar. Annars ljud och/eller länk.
    private func tap(_ e: Element) {
        let deck = session.deck
        var s = session.present
        if Set((deck.slides.indices.contains(index) ? deck.slides[index].revealOrder : [])).subtracting(s.revealed).contains(e.id) {
            session.setPresent(s.revealing(e.id, in: deck))
            return
        }
        if e.isQuiz { session.send(.answer(poll: e.id, shown: !session.live.answers.contains(e.id))) }
        if e.vanishes {
            let wasGone = s.gone.contains(e.id)
            s = s.togglingGone(e.id)
            if wasGone { session.setPresent(s); return }
        }
        if e.sound != nil { s = s.playing(e.id, in: deck) }
        if let link = e.link {
            if case .url(let u) = link { openURL(u) } else if let t = deck.target(of: link, from: index) { s = s.going(to: t, in: deck) }
        }
        session.setPresent(s)
    }

    private func stop() {
        session.setPresent(PresentState(isPresenting: false, slideIndex: index))
        dismiss()
    }
}
