import SwiftUI
import WikiFSCore

/// Entry point for the WikiFS macOS app (Phase 1 — Local wiki).
///
/// Owns the `WikiStoreModel` at App level so a single instance survives the
/// window lifecycle, and flushes any pending autosave when the app stops being
/// active (§3.5 immediate-on-background — don't lose buffered edits on quit).
@main
struct WikiFSApp: App {
    @State private var store: WikiStoreModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Fall back to an in-memory DB only if Application Support is somehow
        // unavailable, so the app still launches rather than crashing.
        let store: WikiStoreModel
        do {
            let url = try DatabaseLocation.applicationSupportURL()
            store = WikiStoreModel(store: try SQLiteWikiStore(databaseURL: url))
        } catch {
            print("WikiFS: falling back to in-memory store: \(error)")
            // swiftlint:disable:next force_try
            let memory = try! SQLiteWikiStore(databaseURL: URL(fileURLWithPath: ":memory:"))
            store = WikiStoreModel(store: memory)
        }
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
        .windowToolbarStyle(.unified)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flushPendingSave() }
        }
    }
}
