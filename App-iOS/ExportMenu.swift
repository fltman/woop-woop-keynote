import SwiftUI
import UniformTypeIdentifiers
import SlideKit

extension UTType {
    static let pptx = UTType("org.openxmlformats.presentationml.presentation") ?? .data
}

private func exportURL(_ deck: Deck, ext: String) -> URL {
    let bad = CharacterSet(charactersIn: "/\\:?*\"<>|")
    let name = deck.title.components(separatedBy: bad).joined().trimmingCharacters(in: .whitespaces)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent((name.isEmpty ? "Presentation" : name) + "." + ext)
}

/// .pptx skapas först när man faktiskt delar. Öppnas i PowerPoint, Keynote och Google Slides.
struct PPTXFile: Transferable {
    let deck: Deck
    let assets: AssetStore
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pptx) { f in
            let url = exportURL(f.deck, ext: "pptx")
            // Diagram, nedräkningar och video blir bilder; lappar och tomma bildplatser tas bort.
            let flat = await MainActor.run { f.deck.flattened(assets: f.assets) }
            try PPTXExporter.export(flat, assets: f.assets).write(to: url)
            return SentTransferredFile(url)
        }
    }
}

struct PDFFile: Transferable {
    let deck: Deck
    let assets: AssetStore
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { f in
            let url = exportURL(f.deck, ext: "pdf")
            let data = await MainActor.run { Snapshot.pdf(f.deck, assets: f.assets) }
            try data.write(to: url)
            return SentTransferredFile(url)
        }
    }
}

struct ExportMenu: View {
    let deck: Deck
    let assets: AssetStore
    var body: some View {
        Menu {
            ShareLink(item: PPTXFile(deck: deck, assets: assets), preview: SharePreview("\(deck.title).pptx")) {
                Label("PowerPoint, Keynote eller Google Slides", systemImage: "rectangle.on.rectangle")
            }
            ShareLink(item: PDFFile(deck: deck, assets: assets), preview: SharePreview("\(deck.title).pdf")) {
                Label("PDF", systemImage: "doc.richtext")
            }
        } label: {
            Label("Exportera", systemImage: "square.and.arrow.up")
        }
    }
}
