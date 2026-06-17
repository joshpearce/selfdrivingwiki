import SwiftUI

/// A trailing inspector for the active agent run. It reuses the operations
/// sheet's transcript renderer so inline page queries do not disappear into a
/// silent lock state.
struct AgentTranscriptSidebar: View {
    @Bindable var launcher: AgentLauncher
    let onCollapse: () -> Void
    @State private var showsInternals = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(PageEditorMetrics.dividerOpacity)
            AgentActivityView(launcher: launcher, showsInternals: showsInternals)
                .padding(AgentTranscriptMetrics.padding)
        }
        .frame(width: AgentTranscriptMetrics.width)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipped()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label("Transcript", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                Toggle("Show internals", isOn: $showsInternals)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if launcher.isRunning {
                    ProgressView()
                        .controlSize(.small)
                    Button("Stop Run", systemImage: "stop.fill") {
                        launcher.stop()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("Stop the running agent")
                }
                Button("Hide Transcript", systemImage: "sidebar.trailing") {
                    onCollapse()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Hide transcript")
            }
        }
        .padding(.horizontal, AgentTranscriptMetrics.padding)
        .padding(.vertical, 10)
    }
}

private enum AgentTranscriptMetrics {
    static let width: CGFloat = 340
    static let padding: CGFloat = 12
}
