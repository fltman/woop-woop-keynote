import SwiftUI
import SlideKit

/// Rita med fingret ovanpå bilden. Teckningen blir en genomskinlig bild som läggs på samma ställe,
/// och kan sedan flyttas, förstoras och få effekter som vilken bild som helst.
struct DrawSheet: View {
    let slide: Slide
    let assets: AssetStore
    var onDone: (Data, Frame) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var strokes: [InkStroke] = []
    @State private var current: InkStroke?
    @State private var color = RGBA(hex: "FF4757")
    @State private var width = 14.0

    private static let colors = ["000000", "FFFFFF", "FF4757", "FFA502", "FFD32A", "2ED573", "1E90FF", "A55EEA", "FF6B81"].map { RGBA(hex: $0) }
    private static let widths = [8.0, 14, 26, 44]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                GeometryReader { geo in
                    let k = geo.size.width / SlideSize.width
                    ZStack {
                        SlideView(slide: slide, assets: assets).opacity(0.55).environment(\.animatesImages, false)
                        Ink(strokes: strokes + (current.map { [$0] } ?? []), k: k)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let p = Spot(x: min(max(v.location.x / k, 0), SlideSize.width), y: min(max(v.location.y / k, 0), SlideSize.height))
                            var s = current ?? InkStroke(points: [], color: color, width: width)
                            if let l = s.points.last, hypot(l.x - p.x, l.y - p.y) < 3 { return }
                            s.points.append(p)
                            current = s
                        }
                        .onEnded { _ in
                            if let s = current { strokes.append(s) }
                            current = nil
                        })
                }
                .aspectRatio(SlideSize.width / SlideSize.height, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 6)
                .padding(.horizontal, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Self.colors, id: \.self) { c in
                            Circle().fill(c.color).frame(width: 36, height: 36)
                                .overlay { Circle().stroke(.gray.opacity(0.5), lineWidth: 1) }
                                .overlay { if c == color { Circle().stroke(Color.accentColor, lineWidth: 3).padding(-5) } }
                                .onTapGesture { color = c }
                                .accessibilityLabel("Färg").accessibilityAddTraits(c == color ? [.isButton, .isSelected] : .isButton)
                        }
                        Divider().frame(height: 30)
                        ForEach(Self.widths, id: \.self) { w in
                            Circle().fill(.primary).frame(width: 6 + w * 0.6, height: 6 + w * 0.6)
                                .frame(width: 40, height: 40)
                                .background(w == width ? Color.accentColor.opacity(0.25) : .clear, in: Circle())
                                .onTapGesture { width = w }
                                .accessibilityLabel("Penntjocklek").accessibilityAddTraits(w == width ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
            .padding(.vertical, 8)
            .navigationTitle("Rita")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ångra", systemImage: "arrow.uturn.backward") { _ = strokes.popLast() }.disabled(strokes.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Klar") { finish() }.disabled(strokes.isEmpty) }
            }
        }
    }

    /// Renderar bara ytan där det finns streck, så att bilden blir lagom stor.
    private func finish() {
        let pts = strokes.flatMap(\.points)
        guard let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max(),
              let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max() else { return dismiss() }
        let pad = (strokes.map(\.width).max() ?? 10) / 2 + 4
        let f = Frame(x: minX - pad, y: minY - pad, w: maxX - minX + pad * 2, h: maxY - minY + pad * 2)
        let moved = strokes.map { s -> InkStroke in
            var s = s
            s.points = s.points.map { Spot(x: $0.x - f.x, y: $0.y - f.y) }
            return s
        }
        let r = ImageRenderer(content: Ink(strokes: moved, k: 1).frame(width: f.w, height: f.h))
        r.scale = 1
        r.isOpaque = false
        if let png = r.uiImage?.pngData() { onDone(png, f) }
        dismiss()
    }
}

private struct Ink: View {
    var strokes: [InkStroke]
    var k: Double
    var body: some View {
        Canvas { ctx, _ in
            for s in strokes where !s.points.isEmpty {
                var p = Path()
                p.move(to: CGPoint(x: s.points[0].x * k, y: s.points[0].y * k))
                for pt in s.points.dropFirst() { p.addLine(to: CGPoint(x: pt.x * k, y: pt.y * k)) }
                if s.points.count == 1 { p.addLine(to: CGPoint(x: s.points[0].x * k + 0.1, y: s.points[0].y * k)) }
                ctx.stroke(p, with: .color(s.color.color), style: StrokeStyle(lineWidth: s.width * k, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
