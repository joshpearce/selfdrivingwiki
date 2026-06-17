import SwiftUI

struct SidebarModeRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 18)
        }
        .padding(.vertical, 3)
    }
}
