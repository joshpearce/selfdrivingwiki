import SwiftUI
import WikiFSCore

/// Output-first chat surface for the dedicated Query page. Internal stream-json
/// bookkeeping stays in AgentActivityView behind "Show internals".
struct QueryTranscriptView: View {
    @Bindable var launcher: AgentLauncher

    var body: some View {
        Group {
            if visibleEvents.isEmpty {
                placeholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: QueryTranscriptMetrics.messageSpacing) {
                            ForEach(visibleEvents, id: \.offset) { _, event in
                                QueryTranscriptRow(event: event)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id(Self.bottomAnchor)
                        }
                        .padding(QueryTranscriptMetrics.padding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: launcher.events.count) {
                        withAnimation(.linear(duration: 0.12)) {
                            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var visibleEvents: [(offset: Int, element: AgentEvent)] {
        launcher.events.enumerated().filter { _, event in
            switch event {
            case .result(_, let text):
                return !hasAssistantText(matching: text)
            default:
                return !event.isInternalTranscriptEvent
            }
        }
    }

    private func hasAssistantText(matching text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        return launcher.events.contains { event in
            if case .assistantText(let assistantText) = event {
                return assistantText.trimmingCharacters(in: .whitespacesAndNewlines) == normalized
            }
            return false
        }
    }

    private var placeholder: some View {
        VStack(spacing: 7) {
            Text(launcher.isRunning ? "Waiting for Claude..." : "Ask a question to start a conversation.")
                .font(.headline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            Text("Answers appear here; tool calls and scratch-work stay hidden unless you show internals.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(QueryTranscriptMetrics.emptyStatePadding)
    }

    private static let bottomAnchor = "query-transcript-bottom"
}

private struct QueryTranscriptRow: View {
    let event: AgentEvent

    var body: some View {
        switch event {
        case .userText(let text):
            QueryMessageBubble(role: .user, text: text)
        case .assistantText(let text):
            QueryMessageBubble(role: .assistant, text: text)
        case .result(_, let text):
            if !text.isEmpty {
                QueryMessageBubble(role: .assistant, text: text)
            }
        case .systemInit, .toolUse, .toolResult, .subagent, .raw:
            EmptyView()
        }
    }
}

private struct QueryMessageBubble: View {
    enum Role: Equatable {
        case user
        case assistant
    }

    let role: Role
    let text: String

    var body: some View {
        HStack(alignment: .top) {
            if role == .user {
                Spacer(minLength: QueryTranscriptMetrics.bubbleGutter)
            }
            if role == .assistant {
                VStack(alignment: .leading, spacing: 0) {
                    AgentMarkdownText(markdown: text)
                }
                .frame(maxWidth: QueryTranscriptMetrics.maxBubbleWidth, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                .frame(maxWidth: QueryTranscriptMetrics.maxBubbleWidth, alignment: .trailing)
            }
            if role == .assistant {
                Spacer(minLength: QueryTranscriptMetrics.bubbleGutter)
            }
        }
        .frame(maxWidth: .infinity, alignment: role == .user ? .trailing : .leading)
    }
}

private enum QueryTranscriptMetrics {
    static let padding: CGFloat = 18
    static let emptyStatePadding: CGFloat = 24
    static let messageSpacing: CGFloat = 14
    static let bubbleGutter: CGFloat = 52
    static let maxBubbleWidth: CGFloat = 760
}
