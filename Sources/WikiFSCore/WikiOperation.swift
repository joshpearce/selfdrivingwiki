import Foundation

/// The three discrete `claude -p` operations the app can run against the
/// currently-selected wiki (`plans/llm-wiki.md` Phase C, decision #2): **Ingest**,
/// **Query**, and **Lint**.
///
/// This is a PURE value type — it carries only the per-run inputs (the ingest
/// source, the query text) and knows how to render the operation's **own prompt**.
/// It deliberately does NOT spawn anything: command/env/cwd assembly lives in
/// `OperationCommand` (also pure), and the actual `Process` spawn lives in the
/// app's `AgentLauncher`. Keeping the prompt/command construction pure is what
/// makes the Phase-C deterministic seams unit-testable without a real agent run.
///
/// **DRY against the schema.** The maintainer schema (`SystemPrompt.defaultBody`,
/// projected as `CLAUDE.md`/`AGENTS.md`) is delivered on every run via
/// `--append-system-prompt`, and it documents the layout, the `wikictl` command
/// reference, the read-after-write rule, and the Ingest/Query/Lint workflows. So
/// each operation's `-p` prompt carries only the per-op task plus the dynamic,
/// per-run facts the system prompt cannot contain: the resolved absolute
/// `WIKI_ROOT`, and (for Ingest) the source file's absolute path / (for Query) the
/// question. It does NOT restate the layout map or the `wikictl` cheatsheet — that
/// would duplicate the schema and drift from it.
public enum WikiOperation: Equatable, Sendable {
    /// Summarize one already-ingested source file into the wiki. `sourcePath` is
    /// the source's mount-relative path under `$WIKI_ROOT` (e.g.
    /// `files/by-id/<ulid>.<ext>`), so the agent can `Read` it directly.
    case ingest(sourcePath: String)

    /// Answer a question from the wiki's contents, returning a cited answer.
    case query(question: String)

    /// Health-check the wiki (contradictions, stale claims, orphan pages, missing
    /// cross-refs, concepts lacking a page) and report findings.
    case lint

    /// A short, stable identifier for the operation kind (logging / UI).
    public var kind: Kind {
        switch self {
        case .ingest: .ingest
        case .query: .query
        case .lint: .lint
        }
    }

    public enum Kind: String, CaseIterable, Sendable {
        case ingest
        case query
        case lint

        /// User-facing title for the operation.
        public var title: String {
            switch self {
            case .ingest: "Ingest"
            case .query: "Query"
            case .lint: "Lint"
            }
        }
    }
}

extension WikiOperation {
    /// The operation's OWN prompt — the `-p` argument handed to `claude`. Slim by
    /// design: the maintainer schema (layout, `wikictl` reference, read-after-write
    /// rule, and the full Ingest/Query/Lint workflows) arrives every run via
    /// `--append-system-prompt`, so this prompt carries only the per-op task and the
    /// dynamic per-run facts the schema can't contain.
    ///
    /// - Parameter wikiRoot: the wiki's LIVE mount path, RESOLVED at click time and
    ///   passed in (NOT `$WIKI_ROOT` for the agent to expand). Injecting the
    ///   concrete path is load-bearing: the live Phase-C gate showed the agent
    ///   burning turns discovering the layout and (under the old allowlist) getting
    ///   every `$WIKI_ROOT`-expanded command rejected.
    public func prompt(wikiRoot: String) -> String {
        switch self {
        case .ingest(let sourcePath):
            return Self.ingestPrompt(wikiRoot: wikiRoot, sourcePath: sourcePath)
        case .query(let question):
            return Self.queryPrompt(wikiRoot: wikiRoot, question: question)
        case .lint:
            return Self.lintPrompt(wikiRoot: wikiRoot)
        }
    }

    private static func ingestPrompt(wikiRoot: String, sourcePath: String) -> String {
        """
        Follow the Ingest workflow from your instructions to bring one source into \
        this wiki. Act immediately; do not explore the layout first.

        WIKI_ROOT (resolved, read-only mount): \(wikiRoot)
        Source to ingest (absolute path): \(wikiRoot)/\(sourcePath)

        Work autonomously to completion — do not ask for confirmation. The live app \
        shows your changes as they land.
        """
    }

    private static func queryPrompt(wikiRoot: String, question: String) -> String {
        """
        Follow the Query workflow from your instructions to answer a question from \
        this wiki, citing the pages or files/ paths your answer draws on.

        WIKI_ROOT (resolved, read-only mount): \(wikiRoot)
        Question: \(question)
        """
    }

    private static func lintPrompt(wikiRoot: String) -> String {
        """
        Follow the Lint workflow from your instructions to health-check this wiki \
        and print a clear findings report.

        WIKI_ROOT (resolved, read-only mount): \(wikiRoot)
        """
    }
}
