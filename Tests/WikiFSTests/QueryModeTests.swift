import Foundation
import Testing
@testable import WikiFS
@testable import WikiFSCore

/// Tests for the `QueryMode` enum introduced in Step 4 of plans/sandbox-and-chat-modes.md.
///
/// Two things to pin down:
///   1. The `allowsEdits` property maps correctly (`.ask` → false, `.edit` → true).
///   2. Feeding `mode.allowsEdits` into `AgentLauncher.selectQuerySandbox` produces the
///      physically-correct sandbox — i.e. the mode enum is the single source of truth that
///      routes the sandbox choice, not a parallel boolean.
@MainActor
struct QueryModeTests {

    // MARK: - allowsEdits mapping

    @Test func askModeDoesNotAllowEdits() {
        #expect(QueryMode.ask.allowsEdits == false)
    }

    @Test func editModeAllowsEdits() {
        #expect(QueryMode.edit.allowsEdits == true)
    }

    // MARK: - Linkage: mode.allowsEdits drives sandbox selection

    private let readOnly = SandboxProfile.readOnlyInvocation(
        homePath: "/Users/test", scratchDir: "/Users/test/scratch")
    private let editSandbox = SandboxProfile.invocation(
        homePath: "/Users/test",
        scratchDir: "/Users/test/scratch",
        wikiDBPath: "/Users/test/wiki.sqlite")

    /// `.ask` mode is physically read-only: its `allowsEdits` value fed directly into
    /// `selectQuerySandbox` must always yield the read-only sandbox, even when a
    /// non-nil edit sandbox is also available.
    @Test func askModeSelectsReadOnlySandbox() {
        let selected = AgentLauncher.selectQuerySandbox(
            allowWikiEdits: QueryMode.ask.allowsEdits,
            editSandbox: editSandbox,
            readOnlySandbox: readOnly)
        #expect(selected == readOnly)
    }

    /// `.edit` mode selects the edit sandbox via its `allowsEdits` value.
    @Test func editModeSelectsEditSandbox() {
        let selected = AgentLauncher.selectQuerySandbox(
            allowWikiEdits: QueryMode.edit.allowsEdits,
            editSandbox: editSandbox,
            readOnlySandbox: readOnly)
        #expect(selected == editSandbox)
    }
}
