import SwiftUI
import WikiFSCore

struct SidebarPageRow: View {
    let summary: WikiPageSummary

    var body: some View {
        Label {
            Text(displayTitle)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Image(systemName: "doc.text")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 16)
        }
        .padding(.vertical, 2)
        .help(displayTitle)
    }

    private var displayTitle: String {
        summary.title.isEmpty ? "Untitled" : summary.title
    }
}
