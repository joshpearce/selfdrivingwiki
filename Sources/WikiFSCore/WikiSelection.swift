/// What the sidebar currently has selected. The sidebar is a single
/// `List(selection:)`, so its selection must be ONE `Hashable` type — this enum
/// unifies the singleton system-prompt document with the wiki pages. Ingested
/// files are intentionally NOT a case: their rows carry no tag and never feed
/// the selection (they open in their default app instead).
public enum WikiSelection: Hashable, Sendable {
    /// The user-editable system-prompt document (`CLAUDE.md` / `AGENTS.md`).
    case systemPrompt
    /// A wiki page, by id.
    case page(PageID)
}
