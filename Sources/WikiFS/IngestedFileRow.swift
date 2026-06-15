import SwiftUI
import WikiFSCore

/// One row in the sidebar's "Files" section: an ingested file's name + size,
/// with a remove affordance via context menu and trailing swipe. Management-only
/// — it deliberately carries NO `.tag(...)`, so it never participates in the
/// page-`List(selection:)` binding (clicking it must not load a phantom page).
struct IngestedFileRow: View {
    let file: IngestedFileSummary
    let onRemove: () -> Void

    var body: some View {
        Label {
            HStack(spacing: 8) {
                Text(file.filename.isEmpty ? "Untitled" : file.filename)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(Self.sizeFormatter.string(fromByteCount: Int64(file.byteSize)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: Self.symbol(forExtension: file.ext))
        }
        .contextMenu {
            Button("Remove", role: .destructive, action: onRemove)
        }
        .swipeActions(edge: .trailing) {
            Button("Remove", role: .destructive, action: onRemove)
        }
    }

    /// An SF Symbol chosen by extension: rich-text doc for PDFs, plain-text doc
    /// for txt/markdown, generic doc otherwise.
    private static func symbol(forExtension ext: String) -> String {
        switch ext {
        case "pdf": return "doc.richtext"
        case "txt", "md", "markdown": return "doc.plaintext"
        default: return "doc"
        }
    }

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
