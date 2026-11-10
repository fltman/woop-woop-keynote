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
    //
    // Tänkt för en hand: det man läser (anteckningarna) får mest plats, det man trycker på ligger
    // nederst vid tummen, och "Härnäst" säger alltid vad nästa tryck gör.

    private var presenter: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if wide {
                    HStack(spacing: 14) {
                        VStack(spacing: 10) { topRow; current; Spacer(minLength: 0) }
                        VStack(spacing: 10) { upNext; notesBox; toolRow; navRow }.frame(width: geo.size.width * 0.42)
                    }
                    .padding(12)
                } else {
                    VStack(spacing: 10) {
                        topRow
                        current
                        upNext
                        notesBox
                        toolRow
                        navRow
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .light), trigger: session.present.revealed.count + session.present.slideIndex * 100)
    }

    private var slide: Slide? { session.deck.slides[safe: index] }
    /// Nästa dolda element på bilden, om det finns något kvar att visa.
    private var nextReveal: Element? {
        guard let s = slide, let id = s.revealOrder.first(where: { !session.present.revealed.contains($0) }) else { return nil }
        return s.element(id)
    }
    private var isLastStep: Bool { nextReveal == nil && index >= session.deck.slides.count - 1 }

    private var current: some View {
        slides
            .aspectRatio(SlideSize.width / SlideSize.height, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                // Tydligt att fingret nu pekar eller ritar i stället för att bläddra.
                if tool != nil { RoundedRectangle(cornerRadius: 10).stroke(Color.yellow, lineWidth: 3) }
            }
            .overlay(alignment: .bottom) {
                if let tool {
                    Text(tool == .laser ? "Dra på bilden för att peka" : "Dra på bilden för att rita")
                        .font(.caption.bold()).foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.yellow, in: Capsule()).padding(6)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if tool == nil { session.remote(.next) } }
            .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                guard tool == nil else { return }
                if v.translation.width < -40 { session.remote(.next) } else if v.translation.width > 40 { session.remote(.previous) }
            })
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            closeButton
            Text("Bild \(index + 1) av \(session.deck.slides.count)").font(.headline.monospacedDigit())
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let s = max(Int(ctx.date.timeIntervalSince(started)), 0)
                Button { started = Date() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                        Text(String(format: "%d:%02d", s / 60, s % 60)).monospacedDigit()
                    }
                    .font(.title3.bold())
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.white.opacity(0.12), in: Capsule())
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Tid sedan start, \(s / 60) minuter \(s % 60) sekunder. Tryck för att nollställa.")
            }
        }
    }

    /// Vad nästa tryck gör: visar ett dolt element, byter bild eller avslutar.
    private var upNext: some View {
        HStack(spacing: 12) {
            Group {
                if nextReveal != nil {
                    Image(systemName: "hand.tap.fill").font(.title2).foregroundStyle(.purple)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.purple.opacity(0.18))
                } else if let next = session.deck.slides[safe: index + 1] {
                    SlideView(slide: next, assets: session.assets, assetVersion: session.assetVersion)
                        .environment(\.animatesImages, false)
                } else {
                    Image(systemName: "flag.checkered").font(.title2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.08))
                }
            }
            .frame(width: 96, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text("Härnäst").font(.caption.bold()).foregroundStyle(.secondary)
                Text(upNextText).font(.subheadline.bold()).lineLimit(2)
            }
            Spacer(minLength: 0)
            if let s = slide, !s.revealOrder.isEmpty {
                // En prick per dolt element på bilden: fyllda är redan visade.
                HStack(spacing: 5) {
                    ForEach(s.revealOrder, id: \.self) { id in
                        Circle().fill(session.present.revealed.contains(id) ? Color.purple : Color.white.opacity(0.25))
                            .frame(width: 9, height: 9)
                    }
                }
                .accessibilityLabel("\(s.revealOrder.filter { session.present.revealed.contains($0) }.count) av \(s.revealOrder.count) visade")
            }
        }
        .padding(8)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var upNextText: String {
        if let e = nextReveal { return "Visar \(e.definiteName)" }
        if index + 1 < session.deck.slides.count { return "Bild \(index + 2)" }
        return "Det här var sista bilden"
    }

    private var notesBox: some View {
        ScrollView {
            Text(notes.isEmpty ? "Inga anteckningar till den här bilden. Skriv dem under bildens format i redigeraren." : notes)
                .font(notes.isEmpty ? .callout : .title3).foregroundStyle(notes.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .id(index)   // börja överst på varje ny bild
    }

    /// Pekare och penna med namn, och ljudknapparna direkt (ett tryck, ingen meny).
    private var toolRow: some View {
        HStack(spacing: 8) {
            chip("Peka", "dot.circle.and.hand.point.up.left.fill", on: tool == .laser) {
                tool = tool == .laser ? nil : .laser
                session.send(.pointer(nil))
            }
            chip("Rita", "pencil.tip", on: tool == .pen) { tool = tool == .pen ? nil : .pen }
            if !session.live.ink.isEmpty {
                chip("Sudda", "eraser.fill", on: false) { session.send(.clearInk) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Jingle.allCases, id: \.self) { j in
                        Button { session.send(.jingle(j, nonce: UUID())) } label: {
                            Text(j.emoji).font(.title2).frame(width: 48, height: 48)
                                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .accessibilityLabel("Spela ljudet \(j.name)")
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                Text("Ljud").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).offset(x: 2, y: -11)
            }
        }
        .padding(.top, 6)
    }

    private func chip(_ title: String, _ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.body.bold())
                Text(title).font(.system(size: 10, weight: .bold))
            }
            .frame(width: 52, height: 48)
            .foregroundStyle(on ? .black : .white)
            .background(on ? Color.yellow : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Tumzonen: liten tillbaka, stor nästa. På sista steget blir nästa "Avsluta".
    private var navRow: some View {
        HStack(spacing: 10) {
            Button { session.remote(.previous) } label: {
                Image(systemName: "chevron.left").font(.title2.bold()).frame(width: 72, height: 68)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            }
            .disabled(index == 0)
            .opacity(index == 0 ? 0.4 : 1)
            .accessibilityLabel("Förra bilden")
            Button { isLastStep ? stop() : session.remote(.next) } label: {
                HStack {
                    Text(isLastStep ? "Avsluta" : (nextReveal != nil ? "Visa nästa" : "Nästa bild"))
                    Image(systemName: isLastStep ? "checkmark" : "chevron.right")
                }
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(isLastStep ? Color.green : (nextReveal != nil ? Color.purple : Color.accentColor), in: RoundedRectangle(cornerRadius: 16))
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
