import SwiftUI
import CoreImage

extension EnvironmentValues {
    /// Det flyktiga läget (röster, visade svar, publikens adress) för omröstningar på bilden.
    @Entry public var liveState = LiveState()
}

/// QR-koder, sparade så att de inte räknas om i varje bildruta.
@MainActor
enum QR {
    private static var cache: [String: CGImage] = [:]
    static func image(_ text: String) -> CGImage? {
        if let c = cache[text] { return c }
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(text.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        cache[text] = cg
        return cg
    }
}

/// Omröstning eller quiz: frågan, staplar som växer när publiken röstar, och QR-koden att skanna.
struct PollView: View {
    var id: UUID
    var box: PollBox
    var width: Double
    var height: Double
    @Environment(\.liveState) private var live

    var body: some View {
        let counts = live.votes[id] ?? []
        let total = max(counts.reduce(0, +), 1)
        let shown = live.answers.contains(id) && box.correct != nil
        let n = Double(max(box.options.count, 1))
        let pad = min(width, height) * 0.06
        let qSize = min(height * 0.13, 84)
        let rowH = min((height - pad * 2 - qSize * 1.5) / n, 170)
        let qr = live.audienceURL.flatMap { QR.image($0) }
        let qrSide = min(height * 0.42, width * 0.24)

        HStack(alignment: .top, spacing: pad) {
            VStack(alignment: .leading, spacing: 0) {
                Text(box.question.isEmpty ? " " : box.question)
                    .font(.custom("Arial", fixedSize: qSize)).bold()
                    .lineLimit(2).minimumScaleFactor(0.5)
                    .frame(height: qSize * 1.5, alignment: .topLeading)
                ForEach(Array(box.options.enumerated()), id: \.offset) { i, option in
                    let c = i < counts.count ? counts[i] : 0
                    let right = shown && box.correct == i
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: rowH * 0.2).fill(box.textColor.color.opacity(0.14))
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: rowH * 0.2)
                                .fill(right ? Color.green : box.accent.color)
                                .frame(width: max(g.size.width * Double(c) / Double(total), c > 0 ? rowH * 0.4 : 0))
                        }
                        HStack {
                            Text((right ? "✓ " : "") + option).lineLimit(1).minimumScaleFactor(0.5)
                            Spacer()
                            Text("\(c)").monospacedDigit()
                        }
                        .font(.custom("Arial", fixedSize: rowH * 0.42)).bold()
                        .padding(.horizontal, rowH * 0.3)
                    }
                    .frame(height: rowH * 0.8)
                    .padding(.vertical, rowH * 0.1)
                    .opacity(shown && !right ? 0.45 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let qr {
                VStack(spacing: qrSide * 0.06) {
                    Image(decorative: qr, scale: 1).interpolation(.none).resizable()
                        .frame(width: qrSide, height: qrSide)
                        .padding(qrSide * 0.06).background(Color.white, in: RoundedRectangle(cornerRadius: qrSide * 0.06))
                    Text("Skanna och rösta").font(.custom("Arial", fixedSize: qrSide * 0.11)).bold()
                }
            }
        }
        .foregroundStyle(box.textColor.color)
        .padding(pad)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: pad * 0.8))
        .animation(.spring(duration: 0.5), value: counts)
        .animation(.easeInOut(duration: 0.3), value: shown)
    }
}
