import AppKit
import SwiftUI

/// File Provider spike UI. Register the domain, get a real Unix path, and
/// reveal/copy it so you can `cd` in from Terminal. Throwaway proof-of-plumbing
/// for Phase 0 risk retirement — replaced by the page editor in Phase 1.
struct WelcomeView: View {
    @State private var spike = FileProviderSpike()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("File Provider spike")
                .font(.title)
                .fontWeight(.semibold)

            Text(spike.status)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let path = spike.path {
                pathCard(path)
            }

            HStack(spacing: 12) {
                Button("Register & Mount", systemImage: "play.fill") {
                    Task { await spike.register() }
                }
                .keyboardShortcut(.defaultAction)

                Button("Remove", systemImage: "trash") {
                    Task { await spike.remove() }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await spike.resolvePath() }
    }

    @ViewBuilder
    private func pathCard(_ path: String) -> some View {
        VStack(spacing: 8) {
            Text(path)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(.quaternary, in: .rect(cornerRadius: 8))

            HStack(spacing: 12) {
                Button("Reveal in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                Button("Copy Path", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
            }
            .buttonStyle(.bordered)

            Text("cd \"\(path)\" && ls && cat README.md")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: 460)
    }
}

#Preview {
    WelcomeView()
}
