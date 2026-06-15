import SwiftUI

/// Live, read-only render of the page body. Uses Foundation's built-in
/// `AttributedString(markdown:)` with inline-only interpretation — the accepted
/// v0 choice (INITIAL.md §4 "avoid a full markdown engine"). The body is split
/// on blank lines so paragraphs and headings read as distinct blocks rather
/// than one collapsed run; each block is its own selectable `Text`.
struct MarkdownPreview: View {
    let markdown: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PageEditorMetrics.sectionSpacing) {
                if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Nothing to preview yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        Text(rendered(block))
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PageEditorMetrics.contentInset)
        }
    }

    /// Split the source into paragraph-ish blocks on blank lines.
    private var blocks: [String] {
        markdown
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Render one block, falling back to the raw text if markdown parsing fails.
    private func rendered(_ block: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: block, options: options))
            ?? AttributedString(block)
    }
}

#Preview {
    MarkdownPreview(markdown: "# Hello\n\nThis is **bold** and _italic_ text.")
        .frame(width: 360, height: 240)
}
