import Foundation

/// The app-side decision of HOW to run an Ingest: a single cheap Sonnet pass for a
/// tiny source, or an Opus planner that fans out to Sonnet `ingest-worker`
/// subagents for anything larger (`plans/llm-wiki.md` Phase D /
/// `feature/ingest-fewer-turns` — problem #3, model tiering).
///
/// PURE and unit-tested. The decision is driven purely by source size against a
/// named threshold; the plan then carries the top-level `--model` alias and, for
/// the planned mode, the `--agents` JSON defining one Sonnet `ingest-worker`. The
/// app picks the mode when building the Ingest command; `OperationCommand.build`
/// turns the plan into argv.
///
/// **Model tiering (verified against the installed CLI 2.1.178).** `--model <m>`
/// sets the top-level model; the aliases `opus` and `sonnet` resolve to
/// `claude-opus-4-8` and `claude-sonnet-4-6`. `--agents '{…}'` defines inline
/// subagents that carry their OWN `model` (a smoke test confirmed the worker ran on
/// `claude-sonnet-4-6` while the top level ran on `claude-opus-4-8`). The custom
/// agent's `prompt` does NOT inherit `--append-system-prompt`, so the worker prompt
/// is SELF-SUFFICIENT about `wikictl` + the read-only rule (it embeds
/// `IngestWriteRule.writes`).
public enum IngestPlan: Equatable, Sendable {
  /// A single Sonnet pass does the whole ingest via `wikictl`. No planner, no
  /// `--agents` — cheapest path for a small source.
  case singleSonnet

  /// An Opus planner reads the source + wiki state, plans the page set, fans out to
  /// 2–19 Sonnet `ingest-worker` subagents, then synthesizes `index.md` + the log
  /// entry itself.
  case opusPlanner

  /// The byte threshold below which a source is "tiny" and gets the single-pass
  /// treatment. Text under ~4 KB is tiny; a large PDF is NOT (it exceeds this even
  /// before counting its non-text heft). Chosen so a short note or paragraph stays
  /// cheap while anything substantial gets the planner's fan-out.
  public static let tinySourceByteThreshold = 4096

  /// Pick the mode from the raw source size. The app passes the source's byte size
  /// (from `IngestedFileSummary.byteSize` / the staged bytes); the decision is a
  /// pure function of that size and the threshold.
  public static func decide(sourceByteSize: Int) -> IngestPlan {
    sourceByteSize < tinySourceByteThreshold ? .singleSonnet : .opusPlanner
  }

  /// The top-level `--model` alias: cheap Sonnet for the single pass, Opus for the
  /// planner that does the planning/synthesis.
  public var topLevelModelAlias: String {
    switch self {
    case .singleSonnet: "sonnet"
    case .opusPlanner: "opus"
    }
  }

  /// The `--agents` JSON for the planned mode (one Sonnet `ingest-worker`), or nil
  /// for the single pass (no subagents). Built from `workerPrompt` so the worker's
  /// write rule can't drift from the top-level prompt's.
  public func agentsJSON() -> String? {
    switch self {
    case .singleSonnet:
      return nil
    case .opusPlanner:
      return Self.agentsJSON(workerPrompt: Self.workerPrompt)
    }
  }

  /// The self-sufficient `ingest-worker` subagent prompt. Because a custom agent's
  /// `prompt` does NOT inherit `--append-system-prompt`, this embeds the FULL write
  /// rule (`IngestWriteRule.writes`) — the worker must know `wikictl` + the
  /// read-only rule on its own. The planner hands each worker its assigned page(s)
  /// and the staged source path in the delegated task.
  public static let workerPrompt = """
    You are an ingest-worker. The planner has assigned you one or a few wiki pages \
    to write for an ingest. Write exactly the page(s) you were assigned — full, \
    well-structured bodies that summarize the assigned material and cross-link \
    related pages with [[Page Title]] — then report tersely which titles you wrote. \
    Do NOT rewrite index.md or append the log; the planner does that after you finish.

    \(IngestWriteRule.writes)

    Read your assigned source material from the staged local path the planner gives \
    you (reliable local disk), not from the read-only mount. After each \
    `wikictl page upsert`, read it back with `wikictl page get` to confirm it landed.
    """

  /// Build the `--agents` JSON object for one Sonnet `ingest-worker`. The shape was
  /// verified against the installed CLI (2.1.178): keys `description`, `prompt`,
  /// `model`, `tools` — `model` is the per-subagent alias (`sonnet`). `tools` is
  /// `["Bash","Read"]` (Bash for `wikictl`, Read for the staged source). JSON is
  /// assembled via `JSONSerialization` so the multi-line prompt is correctly
  /// escaped.
  static func agentsJSON(workerPrompt: String) -> String {
    let agents: [String: Any] = [
      "ingest-worker": [
        "description":
          "Writes assigned wiki page(s) for an ingest via wikictl. Use to fan out "
          + "page-writing across the planned page set.",
        "model": "sonnet",
        "prompt": workerPrompt,
        "tools": ["Bash", "Read"],
      ]
    ]
    // Sorted keys so the rendered JSON is deterministic (stable argv → testable,
    // and a stable prompt prefix for caching).
    guard
      let data = try? JSONSerialization.data(
        withJSONObject: agents, options: [.sortedKeys]),
      let json = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }
    return json
  }
}
