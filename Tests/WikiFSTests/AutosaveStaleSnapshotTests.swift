import Foundation
import Testing
@testable import WikiFSCore

/// The mandated SWIFTUI-RULES §3.5 / §9.4 regression: switching pages while an
/// autosave debounce is pending must flush the OUTGOING page's CURRENT draft
/// (read live at save time), not a stale snapshot — and `summaries` must be
/// rebuilt from the store, never patched. Locks in:
///   1. page-switch flush (select() flushes synchronously first)
///   2. live-read-at-fire-time (save reads draftBody at call time)
///   3. summaries rebuilt from source
@MainActor
struct AutosaveStaleSnapshotTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wikifs-autosave-\(UUID().uuidString).sqlite")
    }

    @Test func pageSwitchFlushesCurrentDraftThenLoadsNewPage() throws {
        let url = tempURL()
        let model = WikiStoreModel(store: try SQLiteWikiStore(databaseURL: url))

        // Create A and B (newPage selects the just-created page).
        model.newPage(title: "A")
        let aID = model.selection!
        model.newPage(title: "B")
        let bID = model.selection!

        // Select A, type into the body, schedule (but DON'T await) the debounce.
        model.select(aID)
        model.draftBody = "A-edit"
        model.bodyChanged()  // 500ms debounce now pending, not yet fired

        // Switch to B BEFORE the debounce fires. This must flush A's CURRENT
        // draft synchronously and then load B.
        model.select(bID)

        // B is now loaded with its (empty) body; A's edit was flushed.
        #expect(model.selection == bID)
        #expect(model.draftBody == "")

        // Reload A from the store and confirm the live draft persisted.
        model.select(aID)
        #expect(model.draftBody == "A-edit")

        // Now mutate B, flush, reopen the store at the same URL, and confirm
        // BOTH pages persisted their latest text.
        model.select(bID)
        model.draftBody = "B-edit"
        model.bodyChanged()
        model.flushPendingSave()

        // selection is now a WikiSelection; pull the page ids back out to read.
        guard case let .page(aPageID) = aID, case let .page(bPageID) = bID else {
            Issue.record("expected page selections"); return
        }
        let reopened = try SQLiteWikiStore(databaseURL: url)
        #expect(try reopened.getPage(id: aPageID).bodyMarkdown == "A-edit")
        #expect(try reopened.getPage(id: bPageID).bodyMarkdown == "B-edit")
    }

    @Test func summariesRebuiltFromSourceAfterMutations() throws {
        let model = WikiStoreModel(store: try SQLiteWikiStore(databaseURL: tempURL()))
        model.newPage(title: "First")
        model.newPage(title: "Second")
        #expect(model.summaries.count == 2)

        let firstID = model.summaries.first { $0.title == "First" }!.id
        model.delete(firstID)
        // Rebuilt from source — not a stale cache.
        #expect(model.summaries.count == 1)
        #expect(model.summaries.allSatisfy { $0.title != "First" })
    }

    /// The List-driven path: SwiftUI writes `selection` directly, then the view
    /// calls `handleSelectionChange(to:)`. This must flush the outgoing page's
    /// live draft and load the incoming page — the same guarantee as `select`.
    @Test func listSelectionChangeFlushesAndLoads() throws {
        let url = tempURL()
        let model = WikiStoreModel(store: try SQLiteWikiStore(databaseURL: url))
        model.newPage(title: "A")
        let aID = model.selection!
        model.newPage(title: "B")
        let bID = model.selection!

        // Simulate List selecting A (binding writes selection, view fires onChange).
        model.selection = aID
        model.handleSelectionChange(to: aID)
        model.draftBody = "A via list"
        model.bodyChanged()

        // Now the List selects B before the debounce fires.
        model.selection = bID
        model.handleSelectionChange(to: bID)
        #expect(model.draftBody == "")  // B is empty, A's edit was flushed

        model.selection = aID
        model.handleSelectionChange(to: aID)
        #expect(model.draftBody == "A via list")
    }

    @Test func renameUpdatesSummaryFromSource() throws {
        let model = WikiStoreModel(store: try SQLiteWikiStore(databaseURL: tempURL()))
        model.newPage(title: "Old Name")
        guard case let .page(id)? = model.selection else {
            Issue.record("expected a page selection"); return
        }
        model.rename(id, to: "New Name")
        #expect(model.summaries.first { $0.id == id }?.title == "New Name")
        #expect(model.draftTitle == "New Name")
    }
}
