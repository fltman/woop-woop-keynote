import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import SlideKit

/// Ljud på ett element: spela in med mikrofonen eller välj en ljudfil.
/// Spelas när man trycker på elementet i presentationen (eller när det visas).
struct SoundControls: View {
    let session: Session
    let slideID: UUID
    let element: Element
    @State private var recorder: AVAudioRecorder?
    @State private var importing = false
    @State private var problem: String?

    /// Inspelningen stannar själv efter en minut, men finns kvar att spara tills man trycker Stoppa.
    private var recording: Bool { recorder != nil }

    var body: some View {
        if let snd = element.sound {
            HStack {
                Label("Ljud", systemImage: "speaker.wave.2.fill")
                Spacer()
                Button("Lyssna", systemImage: "play.fill") { SoundPlayer.shared.preview(snd, assets: session.assets) }
                    .labelStyle(.iconOnly)
                Button("Ta bort ljudet", systemImage: "trash", role: .destructive) { set(nil) }
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
        Button(recording ? "Stoppa inspelningen" : (element.sound == nil ? "Spela in ett ljud" : "Spela in ett nytt ljud"),
               systemImage: recording ? "stop.circle.fill" : "mic.fill") {
            recording ? stopRecording() : startRecording()
        }
        .foregroundStyle(recording ? .red : .accentColor)
        Button("Välj en ljudfil", systemImage: "music.note") { importing = true }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
                guard case .success(let url) = result else { return }
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    set(try session.assets.importAudio(data, ext: url.pathExtension.isEmpty ? "m4a" : url.pathExtension))
                } catch AssetError.tooLarge { problem = "Ljudfilen är för stor (max 15 MB)." }
                catch { problem = "Kunde inte läsa ljudfilen." }
            }
        if let problem { Text(problem).font(.footnote).foregroundStyle(.red) }
    }

    private func set(_ asset: String?) {
        guard var e = session.deck.slide(slideID)?.element(element.id) else { return }
        e.sound = asset
        session.perform(.upsertElement(slide: slideID, e, at: nil))
    }

    private func startRecording() {
        Task {
            guard await AVAudioApplication.requestRecordPermission() else {
                problem = "Woop Woop får inte använda mikrofonen. Slå på det i Inställningar."
                return
            }
            let s = AVAudioSession.sharedInstance()
            try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try? s.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("inspelning-\(UUID()).m4a")
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100,
                                           AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
            guard let r = try? AVAudioRecorder(url: url, settings: settings) else { problem = "Kunde inte spela in."; return }
            r.record(forDuration: 60)   // högst en minut
            recorder = r
            problem = nil
        }
    }

    private func stopRecording() {
        guard let r = recorder else { return }
        r.stop()
        recorder = nil
        if let data = try? Data(contentsOf: r.url), let id = try? session.assets.importAudio(data, ext: "m4a") { set(id) }
        try? FileManager.default.removeItem(at: r.url)
    }
}
