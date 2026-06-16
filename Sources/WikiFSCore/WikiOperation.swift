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
/// ⚠️ **Self-sufficient prompts.** The per-wiki `system_prompt` singleton is still
/// the Phase-D stub, so each operation's own prompt must spell out how to act with
/// `wikictl` (write via `wikictl page upsert`, record via `wikictl log append`,
/// rewrite via `wikictl index set`, read-back via `wikictl page get` because the
/// mount lags ~5s). This makes the structural Phase-C gate pass before Phase D
/// lands the real schema.
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
    /// The operation's OWN prompt — the `-p` argument handed to `claude`. Written
    /// to be self-sufficient against today's stub `system_prompt`: it leads with a
    /// concrete MAP of the wiki (resolved absolute root, layout, `wikictl`
    /// cheatsheet) so the agent acts immediately instead of probing for structure,
    /// then tells it exactly which `wikictl` calls to make.
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

    /// The concrete, load-bearing layout map prepended to every operation prompt.
    /// Carries the RESOLVED absolute `wikiRoot` (so the agent never has to expand
    /// `$WIKI_ROOT`), the fixed projection layout, and the `wikictl` cheatsheet —
    /// the same map `TREE.md` serves, inlined so the agent has it without a read.
    private static func toolingPreamble(wikiRoot: String) -> String {
        """
        You maintain a wiki stored in SQLite, projected read-only at this absolute \
        path (the WIKI_ROOT — browse it with find/cat/grep/Read):
          \(wikiRoot)
        WRITE only through the `wikictl` command — never edit files under the mount, \
        it is read-only. `wikictl` is on your PATH and already targets THIS wiki via \
        the WIKI_DB environment variable, so do NOT pass --wiki. After any write, \
        read it back with `wikictl page get` (NOT by cat-ing the mount, which lags a \
        few seconds). The full layout is also in \(wikiRoot)/TREE.md.

        Layout under \(wikiRoot):
          index.md            curated catalog (rewrite wholesale via `wikictl index set`)
          log.md              append-only chronological log
          TREE.md             this layout/orientation map
          CLAUDE.md / AGENTS.md   the agent system prompt (identical)
          manifest.json       generated wiki manifest
          pages/by-title/     one file per page, by title
          pages/by-id/        the same pages, by ULID
          files/by-name/      raw immutable ingested sources, by filename
          files/by-id/        the same raw sources, by ULID
          indexes/*.jsonl     machine indexes (pages.jsonl, links.jsonl, files.jsonl)

        wikictl cheatsheet:
          wikictl page list                         list id / title / path per page
          wikictl page get --title T | --id I       print a page body (instant, authoritative)
          printf '%s' "<body>" | wikictl page upsert --title T --body-file -   create/update a page
          printf '%s' "<body>" | wikictl index set --body-file -               rewrite index.md
          wikictl log append --kind ingest|query|lint --title "…" [--note "…"]  record an action
        Use [[Page Title]] wiki-links in page bodies to cross-reference other pages.
        """
    }

    private static func ingestPrompt(wikiRoot: String, sourcePath: String) -> String {
        """
        \(toolingPreamble(wikiRoot: wikiRoot))

        TASK — Ingest a source into the wiki. Act immediately; do not explore first.
        The source to ingest is at this absolute path:
          \(wikiRoot)/\(sourcePath)
        Read it (use the Read tool for PDFs/images; cat for text). Then:
          1. Write at least one summary page capturing the source's key content,
             via `wikictl page upsert`. Cite the source by its files/ path.
          2. Create or update any relevant entity/concept pages it mentions,
             cross-linking with [[wiki-links]].
          3. Rewrite the curated index at index.md via `wikictl index set` so it
             lists the pages you just wrote (read the current index first with
             `wikictl page list`).
          4. Append a log entry recording this ingest:
             `wikictl log append --kind ingest --title "<source name>" --note "<one line>"`.
        Work autonomously to completion — do not ask for confirmation. The live
        app shows your changes as they land.
        """
    }

    private static func queryPrompt(wikiRoot: String, question: String) -> String {
        """
        \(toolingPreamble(wikiRoot: wikiRoot))

        TASK — Answer a question from the wiki.
        Question: \(question)
        Search the wiki (`wikictl page list`, then `wikictl page get`, plus
        grep/cat over \(wikiRoot)/index.md and \(wikiRoot)/log.md) and answer
        concisely. CITE the page titles or files/ paths your answer draws on. If the
        wiki lacks the information, say so plainly rather than guessing. You MAY file
        the answer back as a page via `wikictl page upsert` if it would be useful to
        keep, then append `wikictl log append --kind query --title "<the question>"`.
        """
    }

    private static func lintPrompt(wikiRoot: String) -> String {
        """
        \(toolingPreamble(wikiRoot: wikiRoot))

        TASK — Health-check the wiki and report.
        Survey the wiki (page list via `wikictl page list`, bodies via
        `wikictl page get`, the link graph in \(wikiRoot)/indexes/links.jsonl, plus
        index.md and log.md). Report on:
          • contradictions or claims that disagree across pages,
          • stale claims that look outdated,
          • orphan pages (no inbound [[links]]),
          • missing cross-references between related pages,
          • concepts mentioned repeatedly but lacking their own page.
        Print a clear findings report. Then append
        `wikictl log append --kind lint --title "Wiki lint" --note "<summary of findings>"`.
        You MAY also file the report as a page via `wikictl page upsert` if useful.
        Do not modify existing page content beyond adding cross-reference links you
        are confident about.
        """
    }
}
