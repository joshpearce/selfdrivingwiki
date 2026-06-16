import Foundation
import Testing
@testable import WikiFSCore

/// Tests for Phase C's deterministic seams: the `WikiOperation` prompts, the
/// `OperationCommand` env/argv/cwd construction (the EXACT `claude -p` flag
/// surface + `wikictl`-on-PATH), and the `PathPreflight`. These are the seams the
/// structural gate verifier relies on — kept pure/injectable so they test without
/// a real `claude -p` run.
struct OperationCommandTests {

    // MARK: - OperationCommand construction

    private func buildIngest(
        wikictlDir: String = "/Apps/WikiFS.app/Contents/Helpers",
        basePATH: String = "/usr/bin:/bin"
    ) -> OperationCommand {
        OperationCommand.build(
            operation: .ingest(sourcePath: "files/by-id/01ABC.pdf"),
            wikiRoot: "/Users/me/Library/CloudStorage/WikiFS-Research",
            wikiID: "01WIKIULID",
            systemPrompt: "You are the maintainer.",
            scratchDirectory: "/tmp/scratch-xyz",
            wikictlDirectory: wikictlDir,
            claudeExecutable: "/opt/homebrew/bin/claude",
            baseEnvironment: ["PATH": basePATH, "HOME": "/Users/me"]
        )
    }

    @Test func usesResolvedClaudeExecutable() {
        #expect(buildIngest().executable == "/opt/homebrew/bin/claude")
    }

    @Test func argumentsCarryPromptStreamFlagsAppendSystemPromptAndSkipPermissions() {
        let cmd = buildIngest()
        // -p <prompt> --output-format stream-json --verbose --include-partial-messages
        //   --append-system-prompt <prompt> --dangerously-skip-permissions
        #expect(cmd.arguments[0] == "-p")
        #expect(cmd.arguments[1] == WikiOperation.ingest(sourcePath: "files/by-id/01ABC.pdf")
            .prompt(wikiRoot: "/Users/me/Library/CloudStorage/WikiFS-Research"))
        #expect(cmd.arguments[2] == "--output-format")
        #expect(cmd.arguments[3] == "stream-json")
        #expect(cmd.arguments[4] == "--verbose")
        #expect(cmd.arguments[5] == "--include-partial-messages")
        #expect(cmd.arguments[6] == "--append-system-prompt")
        #expect(cmd.arguments[7] == "You are the maintainer.")
        // Frictionless mode: bypass permission checks entirely (the fine-grained
        // allowlist is incompatible with the env-var paths and compound commands the
        // design depends on, and `-p` mode has no approval prompt). Verified accepted
        // by the installed CLI (2.1.178).
        #expect(cmd.arguments[8] == "--dangerously-skip-permissions")
        // The old fine-grained allowlist pair is gone.
        #expect(!cmd.arguments.contains("--allowedTools"))
    }

    @Test func streamJSONRequiresVerbose() {
        // The installed CLI (2.1.178) errors with "When using --print,
        // --output-format=stream-json requires --verbose" if --verbose is absent —
        // so the two flags must always travel together.
        let args = buildIngest().arguments
        #expect(args.contains("--output-format"))
        #expect(args.contains("stream-json"))
        #expect(args.contains("--verbose"))
    }

    @Test func usesSkipPermissionsNotAFineGrainedAllowlist() {
        let cmd = buildIngest()
        // Frictionless mode: exactly one permission flag, the bypass — no allowlist.
        #expect(cmd.arguments.contains("--dangerously-skip-permissions"))
        #expect(!cmd.arguments.contains("--allowedTools"))
        #expect(!cmd.arguments.contains("--allowed-tools"))
        // Nothing left referencing the old scoped Bash allowlist.
        #expect(!cmd.arguments.contains { $0.contains("Bash(wikictl") })
    }

    @Test func environmentExportsWikiRootAndWikiDB() {
        let cmd = buildIngest()
        #expect(cmd.environment["WIKI_ROOT"] == "/Users/me/Library/CloudStorage/WikiFS-Research")
        #expect(cmd.environment["WIKI_DB"] == "01WIKIULID")
    }

    @Test func prependsWikictlDirectoryToChildPATH() {
        let cmd = buildIngest(wikictlDir: "/Apps/WikiFS.app/Contents/Helpers", basePATH: "/usr/bin:/bin")
        // The helper dir must come FIRST so `wikictl` resolves, but the base PATH
        // is preserved so find/cat/grep still resolve too.
        #expect(cmd.environment["PATH"] == "/Apps/WikiFS.app/Contents/Helpers:/usr/bin:/bin")
    }

    @Test func cwdIsTheWritableScratchDirNotTheMount() {
        let cmd = buildIngest()
        #expect(cmd.currentDirectoryPath == "/tmp/scratch-xyz")
        // The mount is read-only; the cwd must never be it.
        #expect(cmd.currentDirectoryPath != "/Users/me/Library/CloudStorage/WikiFS-Research")
    }

    @Test func inheritsBaseEnvironment() {
        let cmd = buildIngest()
        #expect(cmd.environment["HOME"] == "/Users/me")
    }

    @Test func eachOperationKindBuildsAValidCommand() {
        for operation: WikiOperation in [
            .ingest(sourcePath: "files/by-id/01X.txt"),
            .query(question: "How does X compare to Y?"),
            .lint,
        ] {
            let cmd = OperationCommand.build(
                operation: operation,
                wikiRoot: "/mount",
                wikiID: "01W",
                systemPrompt: "schema",
                scratchDirectory: "/scratch",
                wikictlDirectory: "/helpers",
                claudeExecutable: "claude",
                baseEnvironment: [:]
            )
            #expect(cmd.arguments[0] == "-p")
            #expect(cmd.arguments[1] == operation.prompt(wikiRoot: "/mount"))
            #expect(cmd.arguments.contains("--dangerously-skip-permissions"))
            #expect(cmd.environment["WIKI_DB"] == "01W")
        }
    }

    // MARK: - WikiOperation prompts

    private static let resolvedRoot = "/Users/me/Library/CloudStorage/WikiFS-Research"

    @Test func ingestPromptResolvesTheSourcePathAndDefersToTheSchemaWorkflow() {
        let prompt = WikiOperation.ingest(sourcePath: "files/by-id/01ABC.pdf")
            .prompt(wikiRoot: Self.resolvedRoot)
        // The source is given as a RESOLVED absolute path — not `$WIKI_ROOT/…` for
        // the agent to expand (the live gate showed env-var expansion is what the
        // permission system choked on, and the agent hunting for the path).
        #expect(prompt.contains("\(Self.resolvedRoot)/files/by-id/01ABC.pdf"))
        #expect(!prompt.contains("$WIKI_ROOT/files/by-id/01ABC.pdf"))
        // The prompt names the Ingest workflow but DEFERS its steps to the schema
        // (CLAUDE.md, delivered via --append-system-prompt) — it no longer inlines
        // the per-step wikictl cheatsheet.
        #expect(prompt.contains("Ingest workflow"))
        #expect(prompt.lowercased().contains("from your instructions"))
    }

    @Test func queryPromptCarriesTheQuestionAndDefersToTheSchemaWorkflow() {
        let prompt = WikiOperation.query(question: "What is the auth flow?")
            .prompt(wikiRoot: Self.resolvedRoot)
        #expect(prompt.contains("What is the auth flow?"))
        #expect(prompt.contains("Query workflow"))
        #expect(prompt.lowercased().contains("cit"))   // "citing the pages…"
    }

    @Test func lintPromptNamesTheWorkflowAndDefersToTheSchema() {
        let prompt = WikiOperation.lint.prompt(wikiRoot: Self.resolvedRoot)
        #expect(prompt.contains("Lint workflow"))
        #expect(prompt.lowercased().contains("from your instructions"))
    }

    @Test func everyPromptIsSlimCarryingTheResolvedRootButNotTheSchemaDuplication() {
        for operation: WikiOperation in [
            .ingest(sourcePath: "f"),
            .query(question: "q"),
            .lint,
        ] {
            let prompt = operation.prompt(wikiRoot: Self.resolvedRoot)
            // The RESOLVED absolute root is still injected (the one per-run fact the
            // schema can't contain), and is labelled WIKI_ROOT.
            #expect(prompt.contains(Self.resolvedRoot))
            #expect(prompt.contains("WIKI_ROOT"))
            // Each prompt defers to the schema's workflow rather than restating it.
            #expect(prompt.lowercased().contains("from your instructions"))
            // The Phase-C inline duplication is GONE — these now live ONLY in the
            // system prompt (CLAUDE.md), delivered via --append-system-prompt:
            //   the layout map,
            #expect(!prompt.contains("pages/by-title/"))
            #expect(!prompt.contains("files/by-name/"))
            #expect(!prompt.contains("TREE.md"))
            //   the wikictl cheatsheet,
            #expect(!prompt.contains("wikictl page upsert"))
            #expect(!prompt.contains("wikictl index set"))
            #expect(!prompt.contains("wikictl page list"))
            //   and the read-after-write / do-not-pass-wiki reminders.
            #expect(!prompt.contains("wikictl page get"))
            #expect(!prompt.contains("do NOT pass --wiki"))
        }
    }

    @Test func operationKindTitlesAreStable() {
        #expect(WikiOperation.ingest(sourcePath: "f").kind == .ingest)
        #expect(WikiOperation.query(question: "q").kind == .query)
        #expect(WikiOperation.lint.kind == .lint)
        #expect(WikiOperation.Kind.ingest.title == "Ingest")
        #expect(WikiOperation.Kind.query.title == "Query")
        #expect(WikiOperation.Kind.lint.title == "Lint")
    }

    // MARK: - PathPreflight

    @Test func preflightFindsExecutableOnPath() {
        let result = PathPreflight.resolve(
            executable: "claude",
            onPath: "/usr/bin:/opt/homebrew/bin:/bin",
            fileExists: { $0 == "/opt/homebrew/bin/claude" }
        )
        #expect(result == .found(path: "/opt/homebrew/bin/claude"))
    }

    @Test func preflightReportsMissingWhenNotOnPath() {
        let result = PathPreflight.resolve(
            executable: "claude",
            onPath: "/usr/bin:/bin",
            fileExists: { _ in false }
        )
        guard case .missing(let reason) = result else {
            Issue.record("expected .missing")
            return
        }
        #expect(reason.contains("claude"))
        #expect(reason.contains("PATH"))
    }

    @Test func preflightHonorsPathOrderFirstHitWins() {
        let result = PathPreflight.resolve(
            executable: "claude",
            onPath: "/a:/b:/c",
            fileExists: { $0 == "/b/claude" || $0 == "/c/claude" }
        )
        #expect(result == .found(path: "/b/claude"))
    }

    @Test func preflightTestsAbsolutePathDirectlyWithoutPath() {
        let found = PathPreflight.resolve(
            executable: "/opt/claude",
            onPath: "",
            fileExists: { $0 == "/opt/claude" }
        )
        #expect(found == .found(path: "/opt/claude"))

        let missing = PathPreflight.resolve(
            executable: "/opt/claude",
            onPath: "",
            fileExists: { _ in false }
        )
        guard case .missing = missing else {
            Issue.record("expected .missing for absent absolute path")
            return
        }
    }

    @Test func preflightEmptyExecutableIsMissing() {
        let result = PathPreflight.resolve(executable: "", onPath: "/bin", fileExists: { _ in true })
        guard case .missing = result else {
            Issue.record("expected .missing for empty executable")
            return
        }
    }
}
