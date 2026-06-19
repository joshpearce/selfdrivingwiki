import SwiftUI
import WikiFSCore

/// One row in the sidebar's "Files" section. Multi-select is handled natively
/// by the List (Shift+Arrow, Shift+Click, Command+Click). Right-click offers
/// Open, Remove, and "Ingest Selected" when this file is part of a selection.
struct IngestedFileRow: View {
    let file: IngestedFileSummary
    let hasBeenIngested: Bool
    /// True while the agent is actively ingesting this file.
    var isIngesting: Bool = false
    /// True when this file is part of the List's multi-selection.
    var isSelected: Bool = false
    let onOpen: () -> Void
    let onRemove: () -> Void
    /// Ingest all currently-selected files (shown in context menu when this
    /// file is part of a multi-file selection).
    var onIngestSelected: (() -> Void)? = nil

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
                if isIngesting {
                    ProgressView()
                        .controlSize(.small)
                        .help("Ingesting…")
                } else {
                    Image(systemName: hasBeenIngested ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.caption)
                        .foregroundStyle(hasBeenIngested ? .green : .secondary)
                        .help(hasBeenIngested ? "Ingested into the wiki" : "Ready to ingest into the wiki")
                }
            }
        } icon: {
            Image(systemName: Self.symbol(forExtension: file.ext))
        }
        .contentShape(Rectangle())
        .contextMenu {
            if isSelected, let onIngestSelected {
                Button("Ingest Selected", systemImage: "text.badge.plus", action: onIngestSelected)
                Divider()
            }
            Button("Open", systemImage: "arrow.up.forward.app", action: onOpen)
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
