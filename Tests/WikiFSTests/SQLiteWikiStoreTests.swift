import Foundation
import SQLite3
import Testing
@testable import WikiFSCore

/// Store-level tests: persistence across reopen, pragmas + schema, slug
/// collision handling, and ULID ordering.
struct SQLiteWikiStoreTests {

    /// Make a fresh on-disk DB URL in a unique temp directory.
    private func tempDatabaseURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wikifs-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("WikiFS.sqlite")
    }

    // MARK: - Persistence across reopen (M0/M1 acceptance as a unit test)

    @Test func persistsAcrossReopen() throws {
        let url = tempDatabaseURL()
        let id: PageID
        do {
            let store = try SQLiteWikiStore(databaseURL: url)
            let page = try store.createPage(title: "Home")
            id = page.id
            try store.updatePage(id: id, title: "Home", body: "# Welcome\n\nbody text")
        }
        // Reopen at the same URL — a brand new store object/connection.
        let reopened = try SQLiteWikiStore(databaseURL: url)
        let page = try reopened.getPage(id: id)
        #expect(page.title == "Home")
        #expect(page.bodyMarkdown == "# Welcome\n\nbody text")
    }

    // MARK: - Pragmas + schema

    @Test func pragmasAndSchema() throws {
        let url = tempDatabaseURL()
        let store = try SQLiteWikiStore(databaseURL: url)

        // Open a separate raw connection to inspect pragmas/schema.
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }

        // journal_mode is a database-level setting (WAL persists in the file
        // header), so a fresh connection sees it. foreign_keys is per-connection
        // and must be read from the store's own connection.
        #expect(scalarText(db, "PRAGMA journal_mode;").lowercased() == "wal")
        #expect(store.pragmaValue("foreign_keys") == "1")

        let tables = Set(rows(db,
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"))
        #expect(tables.isSuperset(of: ["pages", "attachments", "page_links"]))

        let indexes = Set(rows(db,
            "SELECT name FROM sqlite_master WHERE type='index';"))
        #expect(indexes.contains("pages_slug_unique"))

        // user_version guard: reopening must not re-run DDL (no-op bootstrap).
        let userVersion = scalarText(db, "PRAGMA user_version;")
        #expect(userVersion == "1")
        let reopened = try SQLiteWikiStore(databaseURL: url)
        // If bootstrap weren't guarded, the CREATE TABLE would throw here.
        #expect((try? reopened.listPages()) != nil)
        _ = store  // keep first store alive through the test
    }

    // MARK: - Slug collisions

    @Test func duplicateTitlesGetDistinctSlugs() throws {
        let store = try SQLiteWikiStore(databaseURL: tempDatabaseURL())
        let a = try store.createPage(title: "Same Title")
        let b = try store.createPage(title: "Same Title")
        #expect(a.slug == "same-title")
        #expect(b.slug != a.slug)
        #expect(b.slug.hasPrefix("same-title-"))
    }

    @Test func slugifyStripsPunctuationAndCollapsesDashes() {
        #expect(SQLiteWikiStore.slugify("Hello, World!") == "hello-world")
        #expect(SQLiteWikiStore.slugify("  spaced   out  ") == "spaced-out")
        #expect(SQLiteWikiStore.slugify("!!!") == "untitled")
    }

    // MARK: - listPages ordering

    @Test func listPagesOrdersByUpdatedDescending() throws {
        let store = try SQLiteWikiStore(databaseURL: tempDatabaseURL())
        let a = try store.createPage(title: "A")
        let b = try store.createPage(title: "B")
        // Touch A last so it should sort first.
        try store.updatePage(id: a.id, title: "A", body: "later edit")
        let summaries = try store.listPages()
        #expect(summaries.first?.id == a.id)
        #expect(summaries.contains { $0.id == b.id })
    }

    // MARK: - ULID ordering

    @Test func ulidsSortLexicographicallyInCreationOrder() {
        var rng = SystemRandomNumberGenerator()
        var previous = ""
        for offsetMs in stride(from: 0, to: 5000, by: 1000) {
            let date = Date(timeIntervalSince1970: 1_700_000 + Double(offsetMs) / 1000.0)
            let ulid = ULID.generate(at: date, using: &rng)
            #expect(ulid.count == 26)
            if !previous.isEmpty {
                #expect(previous < ulid, "ULID \(previous) should sort before \(ulid)")
            }
            previous = ulid
        }
    }

    // MARK: - raw-connection helpers

    private func scalarText(_ db: OpaquePointer?, _ sql: String) -> String {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return "" }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0)
        else { return "" }
        return String(cString: c)
    }

    private func rows(_ db: OpaquePointer?, _ sql: String) -> [String] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) { out.append(String(cString: c)) }
        }
        return out
    }
}
