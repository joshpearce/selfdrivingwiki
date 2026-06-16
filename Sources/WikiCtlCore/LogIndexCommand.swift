import Foundation
import WikiFSCore

/// The `wikictl log append` and `wikictl index set` subcommands (Phase B),
/// executed against an already-opened `WikiStore`. Split from process concerns
/// (arg parsing, stdin, the Darwin post, opening the DB) so the command surface
/// is unit-testable against a temp DB, exactly like `PageCommand`.
public enum LogIndexCommand {

    public enum Action: Equatable {
        /// Append one dated row to the chronological log.
        case logAppend(kind: LogEntry.Kind, title: String, note: String?)
        /// Replace the singleton wiki-index body wholesale (UPSERT, version + 1).
        case indexSet(body: String)
    }

    /// Run one action against `store`. Both actions COMMIT (the caller posts the
    /// change notification). `logAppend` echoes the new entry's id; `indexSet`
    /// produces no output (the body is wholesale-replaced).
    public static func run(_ action: Action, in store: WikiStore) throws -> PageCommand.Result {
        switch action {
        case .logAppend(let kind, let title, let note):
            let entry = try store.appendLog(kind: kind, title: title, note: note)
            return PageCommand.Result(output: entry.id.rawValue, didCommit: true)
        case .indexSet(let body):
            try store.updateWikiIndex(body: body)
            return PageCommand.Result(output: "", didCommit: true)
        }
    }
}
