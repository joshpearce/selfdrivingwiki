import Foundation

/// The user-editable "system prompt" document — a single, app-wide singleton
/// (NOT a wiki page). It is the first thing the managing agent reads on every
/// run: the File Provider projection surfaces its body read-only at the wiki
/// root as BOTH `CLAUDE.md` and `AGENTS.md` (identical bytes), the two filenames
/// the common CLI agents look for. The user edits it in the app; the projection
/// is read-only like everything else.
///
/// Persisted as one row in the `system_prompt` table (`id = 1`). Carries a
/// `version` (bumped on every edit) so it can fold into the whole-database
/// `changeToken()` sync anchor — editing ONLY the prompt must still advance the
/// anchor or the projected `CLAUDE.md`/`AGENTS.md` would never refresh.
public struct SystemPrompt: Equatable, Sendable {
    public var body: String
    public var updatedAt: Date
    public var version: Int

    public init(body: String, updatedAt: Date, version: Int) {
        self.body = body
        self.updatedAt = updatedAt
        self.version = version
    }

    /// Seeded into a fresh DB (the v2→3 migration) and used as the projection's
    /// fallback when the row/table can't be read (e.g. a read connection opened
    /// against a not-yet-migrated DB), so `CLAUDE.md`/`AGENTS.md` always exist.
    public static let defaultBody = """
    # Wiki Agent Instructions

    You maintain this wiki. The user drops in notes, files, and half-formed
    thoughts; your job is to organize, cross-link, and summarize them — never to
    discard their raw input.

    This document is user-editable and is projected read-only at the wiki root as
    both `CLAUDE.md` and `AGENTS.md`, so it is the first thing you read each run.
    Edit it in the WikiFS app, not through the filesystem.

    ## Layout

    - `pages/by-title/`, `pages/by-id/` — the wiki pages.
    - `files/by-name/`, `files/by-id/` — verbatim dropped files.
    - `indexes/*.jsonl`, `manifest.json` — machine-readable indexes.

    ## Conventions

    - Keep pages well-titled and connected with `[[wiki links]]`.
    - Summarize long or messy notes; preserve the original alongside the summary.

    """
}
