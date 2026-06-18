# Self Driving Wiki

**What this is.** A native macOS SwiftUI wiki backed by SQLite, mirrored
read-only onto the filesystem by a **File Provider extension** so the same
content can be browsed by Unix tools and agents (`find`, `cat`, `grep`) under
`~/Library/CloudStorage/Self Driving Wiki-<wiki name>`. You edit in the app; the
mount reflects every change. It also ingests dropped files (verbatim bytes under
`files/`) and projects a singleton agent system prompt as `CLAUDE.md` +
`AGENTS.md` at the root. Runs locally only — free, local dev signing; no Developer
ID / notarization.

**Core goal (non-negotiable).** This is a proof-of-concept of the macOS **File
Provider API**. The extension is essential, not optional — do **not** replace it
with a plain-folder export, even though that would dodge the signing requirement.

**Where to find things.**

- **This file (`PLAN.md`)** — the master index: the doc map below, milestone
  status, and the build quick-reference.
- **`PROGRESS.md`** — the running log, newest first: what was built each step and
  the evidence each gate passed. *To get a future agent up to speed, read
  `PLAN.md` then `PROGRESS.md`.*
- **`plans/`** — the deep design docs (architecture, build, File Provider,
  signing); see the table below for which is which.
- **`ISSUES.md`** — known limitations we've chosen to live with.
- **`SWIFTUI-RULES.md`** / **`CLAUDE.md`** — coding rules and the working
  agreement (docs to keep, skills to use, PR rules).

## Documentation index

| Doc | What it covers |
| --- | --- |
| [`README.md`](README.md) | **Start here (new developers).** What Self Driving Wiki is, the non-negotiable read-only-mount / write-via-`wikictl` invariant, quick start (`make` targets + the runtime gotchas), repo layout, and a tour of how it works. |
| [`plans/architecture.md`](plans/architecture.md) | **The system map.** Components/targets, the per-wiki SQLite data model + migration ladder + `changeToken()`, the File Provider projection, the read/write split + change bridge, the `claude -p` operations (Ingest tiering, Query, Lint), URL ingest, and the key invariants/gotchas. Read after the README to go deep. |
| [`plans/INITIAL.md`](plans/INITIAL.md) | Original full product/architecture plan (milestones, schema, File Provider design, definition of done). Source of truth for *what we're building*. |
| [`plans/llm-wiki.md`](plans/llm-wiki.md) | **Next major effort:** turning Self Driving Wiki into a self-maintaining LLM Wiki — **many** wikis (one SQLite DB + one File Provider domain each), with `claude -p` authoring/maintaining each one by writing via a new `wikictl` CLI (read via the mount, write via the CLI). Locked decisions, components, and the Phase 0 → A–D plan. Read before Phase 0. |
| [`plans/page-reader-ui.md`](plans/page-reader-ui.md) | **Current UI direction:** page detail is reader-first because the agent should maintain wiki content; manual source editing is an explicit, rare mode. |
| [`plans/query-conversation.md`](plans/query-conversation.md) | **Current Query direction:** a dedicated sidebar page with an interactive Claude session; output-first chat by default, hidden tool/internal rows behind a checkbox, and writes via `wikictl` only when the user asks to persist changes. |
| [`plans/pdf-extraction.md`](plans/pdf-extraction.md) | **Local PDF extraction:** replace Claude `Read`-tool PDF extraction with a local docling + granite-docling pipeline. A `pdf2md` CLI converts PDFs to markdown at ingest time; extracted markdown stored as a sibling `ingested_files` row, projected on the mount. Agent prefers `.md` siblings, falls back to `Read` on the original. |
| [`plans/BRINGUP.md`](plans/BRINGUP.md) | The 4-phase bring-up plan from skeleton to v0 (groups INITIAL.md's M0–M6). Source of truth for *the order we build in*. |
| [`plans/build-environment.md`](plans/build-environment.md) | How the app is built: SwiftPM + `build.sh` + `Makefile`, signing, icon generation, app-bundle layout. Source of truth for *how we build and run*. |
| [`plans/file-provider.md`](plans/file-provider.md) | File Provider extension build + the 5 hard-won gotchas (entry-point recursion, entitlements⊆profile, user-enable toggle, /Applications, keychain). Proven by the 2026-06-15 spike. Read before Phase 2. |
| [`plans/signing.md`](plans/signing.md) | The Apple cert / App Group / File Provider provisioning checklist (manual portal). Do this before Phase 2. Source of truth for *the Apple incantations*. |
| [`SWIFTUI-RULES.md`](SWIFTUI-RULES.md) | Hard-won SwiftUI/macOS rules. Apply when writing or reviewing any view. |
| [`CLAUDE.md`](CLAUDE.md) | Working agreement (docs, skills to use, PR rules). |
| [`ISSUES.md`](ISSUES.md) | Known limitations we've chosen to live with (with context to revisit), e.g. the ~5s replicated-File-Provider read-after-write window. |

## Status

See `PROGRESS.md` for the running log. Current: **🎉 LLM Wiki COMPLETE ✅ — all
five phases (0, A, B, C, D) gate-passed.** Self Driving Wiki is now a self-maintaining LLM
wiki: a user keeps **many** wikis (one SQLite DB + one File Provider domain
each); an LLM (`claude -p`, run as **Ingest / Query / Lint** from the app)
authors and maintains each one — reading the read-only mount and writing via the
new **`wikictl`** CLI — keeping curated `index.md` + chronological `log.md`
current, cross-linking pages with clickable `[[wiki-links]]`, all under a real
maintainer schema projected as `CLAUDE.md`/`AGENTS.md`. Agent runs stream live
(tool calls + text, `--output-format stream-json`) with per-run backend
`run.jsonl` logs and an editor edit-lock. **All five phases plus the post-completion
features below are merged to `main` (single-branch repo, ready for developer
handoff). 341 tests green; clean signed bundle (app + appex + `wikictl`).**

**Post-completion features (also on `main`):**
- **Wiki backup/restore management** — the wiki switcher can rename the active
  wiki, export its checkpointed standalone SQLite file, and import a SQLite wiki
  backup under a new display name/new ULID. Rename refreshes the File Provider
  display name while preserving identity; export refuses to overwrite its source.
- **Ingest model-tiering** — Ingest is now **Opus-curated**: Opus decides what goes
  in the wiki and writes every page; for a large source it fans out **2–19 Sonnet
  `source-reader` subagents** (via `claude -p --agents`) that only *digest* the
  bulk content and return extracts (they never write), and Opus may fork follow-up
  readers / pull pages to double-check. Tiny sources are a single Opus pass. The
  per-run scratch dir stages the source + a live `WIKI_STATE.md` snapshot from
  SQLite so the agent never re-derives structure from the laggy mount.
- **Ingest a resource by URL** — an "Add from URL…" sheet fetches a URL, normalizes
  known file-share links (Dropbox `www`→`dl`; Drive/OneDrive stubbed), content-sniffs
  the bytes, converts HTML→Markdown (hand-rolled, dependency-free) or stores
  PDFs/binaries verbatim — landing through the same ingest path as drag-drop.

**Phase summary (newest first; see `PROGRESS.md` for each gate's evidence):**
- **Phase D — the schema** ✅ real maintainer `CLAUDE.md` schema (layout,
  conventions, `wikictl` reference, read-after-write rule, Ingest/Query/Lint
  playbooks); `-p` prompts slimmed to rely on it; new wikis seed it, existing
  unaffected. Also hardened File Provider domain registration (verify/retry/nudge/
  surface-errors).
- **Phase C — `claude -p` operations** ✅ Ingest/Query/Lint scoped runs +
  `--dangerously-skip-permissions` + layout-up-front (`TREE.md`) + live streaming
  panel + backend logs + per-wiki edit-lock + clickable `[[wiki-links]]`.
- **Phase B — `log.md` + `index.md`** ✅ v3→4 `log` table + v4→5 `wiki_index`
  singleton; `wikictl log append` / `index set`; both projected read-only at root;
  `changeToken()` folds.
- **Phase A — write path + change bridge** ✅ `wikictl` (page upsert/get/list/
  delete) + shared `PageUpsert` link-reparse + per-wiki Darwin notification →
  debounced sidebar rebuild + `signalChange()`.
- **Phase 0 — many wikis** ✅ wiki registry (ULID identity), per-wiki DBs +
  per-wiki File Provider domains, in-app switcher, v0 wiki migrated as wiki #1.

**Prior: LLM Wiki Phase A (Write path + change bridge) DONE ✅ — live gate
passed.** The `wikictl` CLI (`page list/get/upsert/delete`, selecting a wiki via
`--wiki`/`WIKI_DB`) writes straight to a wiki's `<ulid>.sqlite`; a shared
`PageUpsert` op keeps the `[[link]]` graph identical across the app and the CLI;
`wikictl` posts a per-wiki Darwin notification and the app's debounced change
bridge rebuilds the sidebar + `signalChange()`s that wiki's mount. 113 tests;
clean signed bundle (app + appex + `wikictl`). Branch `llmwiki/phase-a-write-path`
(stacked on `llmwiki/phase-0-many-wikis`, unmerged).

**Prior: LLM Wiki Phase 0 (Many wikis) DONE ✅ — live gate passed.** One SQLite DB
+ one File Provider domain **per wiki**, a `wikis.json` registry, an in-app
create/select/delete switcher, and the single v0 wiki migrated in as wiki #1
(idempotently). Branch `llmwiki/phase-0-many-wikis`. See `plans/llm-wiki.md` for
the Phase 0 → A–D plan.

**Prior baseline: 🎉 v0 DONE ✅ — all four phases gate-passed (M0–M6).** A native macOS SwiftUI wiki, SQLite-backed,
projected read-only onto the filesystem via a File Provider extension, kept
fresh on edit, and traversable by an agent launched with `WIKI_ROOT`. Delivered
across four stacked, **unmerged** branches off a pristine `main`
(`phase-1-local-wiki` → `phase-2-file-provider` → `phase-3-verify-fresh` →
`phase-4-agent-wiki`) — review and merge locally. See `PROGRESS.md` for each
gate's evidence and the known v0 gaps.

**Post-v0 features** (also stacked, unmerged):

- `phase-5-file-ingest` — drag a file in to **ingest** it (raw bytes + metadata
  stored in a new `ingested_files` SQLite table, NOT a wiki page; surfaced
  read-only under `files/by-id` & `files/by-name`; removable "Files" list).
  Verified with a real 8 MB PDF served byte-identical from the mount.
- **System-prompt document** — a user-editable singleton "system prompt" (DB
  `system_prompt` table, v2→3 migration) projected **read-only at the wiki root
  as both `CLAUDE.md` and `AGENTS.md`** (identical bytes). Edited in-app via a
  pinned sidebar item. Code complete + unit-tested (69 tests); **live-mount gate
  pending**. See `PROGRESS.md`.

## Milestones (from `plans/INITIAL.md`)

- **M0 — App skeleton** ✅ build environment + launching SwiftUI window.
- **M1 — Markdown editor** ✅ sidebar page list, `TextEditor`, preview, autosave, SQLite persistence.
- **M2 — File Provider domain** ✅ extension target, domain registration, static root + `README.md`.
- **M3 — SQLite-backed page files** ✅ `pages/by-id`, `pages/by-title`, content from SQLite.
- **M4 — Path button** ✅ `Copy Unix Path`, verification commands in-app.
- **M5 — Change signaling** ✅ edits increment version; Terminal reads see updates (no relaunch).
- **M6 — Agent launch** ✅ spawn agent with `WIKI_ROOT` env pointing at the projection.

## Build quick reference

```sh
make          # debug build → build/Self Driving Wiki.app
make run      # build + launch
make check    # compile-only gate (no bundle/sign)
make help     # all targets
```

Full detail: [`plans/build-environment.md`](plans/build-environment.md).
