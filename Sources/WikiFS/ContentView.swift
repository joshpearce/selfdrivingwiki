import SwiftUI

/// Hello-world content for Milestone 0. Intentionally minimal: it proves the
/// SwiftPM → bundle → codesign → launch pipeline works end to end before any
/// real wiki UI lands. The two-column shell foreshadows the eventual
/// sidebar / editor split from PLAN.md without committing to it yet.
struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Label("Welcome", systemImage: "book.closed")
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .navigationTitle("WikiFS")
        } detail: {
            WelcomeView()
        }
    }
}

#Preview {
    ContentView()
}
