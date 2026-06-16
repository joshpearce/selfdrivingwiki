import SwiftUI

/// The "Agent is updating the wiki…" banner shown above the editor while a
/// `claude -p` operation runs against the active wiki (Phase C / decision #6).
///
/// SWIFTUI-RULES §1.1: it is ALWAYS mounted and animates a DIMENSION (its height,
/// via `frame(height:)` + `clipped()`), never its presence — inserting/removing a
/// view with a transition inside hosted SwiftUI risks the constraint-engine crash.
/// Reduce Motion skips the animation entirely.
struct AgentRunBanner: View {
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Agent is updating the wiki…")
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            Text("Editing paused")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: isVisible ? Self.barHeight : 0)
        .frame(maxWidth: .infinity)
        .background(.yellow.opacity(0.18))
        .clipped()
        .accessibilityHidden(!isVisible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isVisible)
    }

    private static let barHeight: CGFloat = 32
}
