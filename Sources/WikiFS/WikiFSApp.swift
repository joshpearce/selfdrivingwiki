import SwiftUI

/// Entry point for the WikiFS macOS app.
///
/// Milestone 0 (App Skeleton) starts here: a single window scene hosting the
/// hello-world content. SQLite, the sidebar, and the File Provider domain
/// arrive in later milestones — see PLAN.md.
@main
struct WikiFSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowToolbarStyle(.unified)
    }
}
