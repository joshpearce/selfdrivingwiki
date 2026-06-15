import SwiftUI
import WikiFSCore

/// Phase 1 shell: a sidebar of pages and a detail pane that either edits the
/// selected page or shows a designed empty state (§7.1 ContentUnavailableView).
/// The Phase 0 spike (WelcomeView / FileProviderSpike) is no longer hosted here
/// but still compiles in this target for Phase 2.
struct ContentView: View {
    @Bindable var store: WikiStoreModel

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            if store.selection == nil {
                ContentUnavailableView {
                    Label("No Page Selected", systemImage: "doc.text")
                } description: {
                    Text("Select a page from the sidebar, or create a new one.")
                } actions: {
                    Button("New Page", systemImage: "plus") { store.newPage() }
                }
            } else {
                PageDetailView(store: store)
            }
        }
        // List(selection:) writes store.selection directly; observe it here so
        // the model flushes the outgoing page and loads the incoming one
        // (§3.5). The view, not the binding, is the right place for this.
        .onChange(of: store.selection) { _, newValue in
            store.handleSelectionChange(to: newValue)
        }
    }
}
