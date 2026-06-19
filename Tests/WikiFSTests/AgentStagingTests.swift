import Foundation
import Testing
@testable import WikiFSCore

/// Tests for the PURE staging seams (`feature/ingest-fewer-turns`): the staged-leaf
/// path math, the `WIKI_STATE.md` rendering, and the worker prompt's self-sufficient
/// write rule. The actual file writes are a thin app seam (`AgentStaging.stage*`);
/// what's pure is tested here.
struct AgentStagingTests {

  // MARK: - Staged leaf names (path math)

  @Test func sourceFileNameAppendsLowercasedExtension() {
    #expect(AgentStaging.sourceFileName(ext: "pdf") == "source.pdf")
    #expect(AgentStaging.sourceFileName(ext: "PDF") == "source.pdf")
    #expect(AgentStaging.sourceFileName(ext: ".md") == "source.md")
    #expect(AgentStaging.sourceFileName(ext: "  txt  ") == "source.txt")
  }

  @Test func sourceFileNameHandlesMissingExtension() {
    #expect(AgentStaging.sourceFileName(ext: "") == "source")
    #expect(AgentStaging.sourceFileName(ext: ".") == "source")
  }

  @Test func stateFileNameIsFixed() {
    #expect(AgentStaging.stateFileName == "WIKI_STATE.md")
  }

  // MARK: - Actual staging (round-trip through a temp dir)

  @Test func stagesStateAndSourceIntoScratchAndReturnsAbsolutePaths() throws {
    let scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }

    let statePath = try AgentStaging.stageStateFile("# WIKI_STATE\nhello", in: scratch)
    let sourcePath = try AgentStaging.stageSource(Data("raw bytes".utf8), ext: "txt", in: scratch)

    #expect(statePath == scratch.appendingPathComponent("WIKI_STATE.md").path)
    #expect(sourcePath == scratch.appendingPathComponent("source.txt").path)
    #expect(try String(contentsOfFile: statePath, encoding: .utf8) == "# WIKI_STATE\nhello")
    #expect(try Data(contentsOf: URL(fileURLWithPath: sourcePath)) == Data("raw bytes".utf8))
  }

  // MARK: - Multi-source staging

  @Test func sourceFileNameWithIndex() {
    #expect(AgentStaging.sourceFileName(ext: "md", index: 1) == "source-1.md")
    #expect(AgentStaging.sourceFileName(ext: "pdf", index: 2) == "source-2.pdf")
    #expect(AgentStaging.sourceFileName(ext: "", index: 3) == "source-3")
    #expect(AgentStaging.sourceFileName(ext: ".txt", index: 10) == "source-10.txt")
  }

  @Test func stagesMultipleSourcesIntoScratch() throws {
    let scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }

    let sources: [(bytes: Data, ext: String)] = [
      (Data("first".utf8), "md"),
      (Data("second".utf8), "pdf"),
    ]
    let paths = try AgentStaging.stageSources(sources, in: scratch)

    #expect(paths.count == 2)
    #expect(paths[0] == scratch.appendingPathComponent("source-1.md").path)
    #expect(paths[1] == scratch.appendingPathComponent("source-2.pdf").path)
    #expect(try Data(contentsOf: URL(fileURLWithPath: paths[0])) == Data("first".utf8))
    #expect(try Data(contentsOf: URL(fileURLWithPath: paths[1])) == Data("second".utf8))
  }

  @Test func stagesEmptySourcesListReturnsEmpty() throws {
    let scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }

    let paths = try AgentStaging.stageSources([], in: scratch)
    #expect(paths.isEmpty)
  }

  // MARK: - WIKI_STATE.md rendering

  @Test func stateFileRendersTitlesIndexAndLog() {
    let snapshot = WikiStateSnapshot.make(
      allTitles: ["Calvin Cycle", "Photosynthesis"],
      indexBody: "# Index\n- [[Calvin Cycle]]",
      logLines: ["## [2026-06-16] ingest | notes.txt"])
    let md = snapshot.renderStateFile()

    #expect(md.contains("# WIKI_STATE"))
    #expect(md.contains("- Calvin Cycle"))
    #expect(md.contains("- Photosynthesis"))
    #expect(md.contains("# Index"))
    #expect(md.contains("## [2026-06-16] ingest | notes.txt"))
    // It tells the agent not to re-fetch the state.
    #expect(md.lowercased().contains("do not need to run `wikictl page list`"))
  }

  @Test func stateFileHandlesFreshAndEmptyWiki() {
    let snapshot = WikiStateSnapshot.make(allTitles: [], indexBody: "", logLines: [])
    let md = snapshot.renderStateFile()
    #expect(md.contains("fresh wiki"))
    #expect(md.contains("Empty."))
  }

  @Test func stateFileNotesTruncatedPageCount() {
    let many = (1...200).map { "Page \($0)" }
    let snapshot = WikiStateSnapshot.make(allTitles: many, indexBody: "", logLines: [])
    let md = snapshot.renderStateFile()
    // Capped at maxListedTitles with a note about the remainder.
    #expect(snapshot.pageTitles.count == WikiStateSnapshot.maxListedTitles)
    #expect(md.contains("and \(200 - WikiStateSnapshot.maxListedTitles) more"))
  }
}
