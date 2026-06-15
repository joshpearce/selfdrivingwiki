# Progress log

Newest first. To get up to speed: read `PLAN.md` then this file.

## 2026-06-15 — Phase 2 (M2+M3): File Provider projection from SQLite — DONE ✅ (gate passed)

The File Provider extension now serves a **read-only filesystem projection of the
SQLite wiki**, shared with the app via the App Group container. Branch
`phase-2-file-provider` (stacked on `phase-1-local-wiki`, unmerged). A swap of
the spike's static `Catalog` for a live SQLite projection — the appex plumbing,
entry-point flag, inside-out signing, and domain registration all carried over.

**Added / changed**
- `Sources/WikiFSFileProvider/Projection.swift` (NEW; `Catalog.swift` deleted) —
  identity↔row mapping, static `README.md`, filename escaping, and
  `node(for:)`/`children(of:)`/`contents(for:)`, each opening a **short-lived
  read connection** to the App Group DB via `extensionContainerURL()`.
  Virtual ids carry the **full ULID, never the filename** (paths are
  presentation — INITIAL §6).
- `WikiFSCore/SQLiteWikiStore.swift` — `init(readOnlyURL:)` opens a read-WRITE
  handle then `PRAGMA query_only=ON` (NOT `SQLITE_OPEN_READONLY`): robustly
  attaches the WAL `-shm` even when no writer is running (matters for Phase-4
  agents reading with the app closed) while still rejecting writes.
- `WikiFSCore/DatabaseLocation.swift` — `appGroupContainerURL()` (literal path,
  used by the un-sandboxed app, no entitlement needed), `extensionContainerURL()`
  (`containerURL(forSecurityApplicationGroupIdentifier:)`, sandboxed extension;
  same inode), `migrateFromApplicationSupportIfNeeded()` (checkpoint-TRUNCATE +
  copy the single `.sqlite`).
- `WikiFSFileProvider/WikiFSItem.swift` — real `documentSize` (=`utf8.count`,
  never nil → no truncated `cat`), `contentType`, creation/mod dates, and
  content/metadata `itemVersion` from the row. Read-only capabilities.
- `WikiFSFileProvider/WikiFSEnumerator.swift` — queries `Projection`,
  offset-paginated (256/page), sync anchor bumped to `"v2-sqlite"` so any cached
  spike enumeration expires.
- `WikiFS/WikiFSApp.swift` + `FileProviderSpike.swift` — open the App Group DB
  (after migration); `registerIfNeeded()` does `remove(_, mode: .removeAll)` then
  `add` on launch so the daemon re-enumerates from the SQLite extension.
- `Package.swift` — extension target depends on `WikiFSCore`; `-e
  _NSExtensionMain` flag + `FileProvider` framework preserved. `build.sh`
  unchanged.
- Tests: +13 (FilenameEscaping, ReadOnlyStore) → **23 total, all pass**.

**Decision — Option B: app stays UN-sandboxed**
Both processes share the literal `~/Library/Group Containers/group.org.sockpuppet.wiki/WikiFS.sqlite`
(app writes the literal path; sandboxed extension resolves the same inode via
`containerURL`). Rejected sandboxing the app (Option A) because it would (1)
redirect `Application Support` and orphan the Phase-1 DB, and (2) front-load the
Phase-4 `Process`/agent-spawn restriction (`signing.md`) for zero Phase-2
benefit. The container dir is user-owned and writable by a non-sandboxed
process. Phase-1's `Home` row **migrated** intact (same ULID
`01KV6EAH410NWC9K9ZM44DNMXT`).

**Verified (independent gate, fresh `make clean && make install`, real-signed)**
- `find .` → `README.md` + `pages/by-id/<ULID>.md` + `pages/by-title/Home--<id8>.md`
  (the SQLite ULID, not the static spike tree).
- `cat` of by-title AND by-id → byte-identical Home body (`VERIFY-7Q4Z` sentinel,
  62 bytes, `shasum b6ef887f…`), exactly matching the SQLite row.
- Read-only: `createItem` → FP -2010; shell writes stage client-side then revert;
  SQLite source of truth never altered. Extension `+`-enabled, fresh appex
  (Timestamp 20:44:24) serving.

**Notes / caveats (carry into Phase 3)**
- **macOS 26 TCC gate:** first App Group access raises *"WikiFS would like to
  access data from other apps"* (Allow/Don't-Allow, NOT Touch ID). It fires
  synchronously in SwiftUI `App.init()`, so the window is hostage to it, and a
  re-signed `make install` re-prompts. Consent persisted across the gate launch.
  *Cleanup idea:* move the DB open off `App.init()` so the window renders while
  the prompt is pending.
- **Read-after-write staleness on EDITS is still present — that's Phase 3's job.**
  The blunt `remove(.removeAll)` refresh on launch is replaced in Phase 3 by
  per-item version bumps + `signalEnumerator`.
- Read-only root: a shell `echo > f` stages then reverts (File Provider client
  framework behavior); never reaches SQLite. Optional polish: disallow
  adding-sub-items on the root capabilities for up-front shell rejection.
- All 5 File Provider gotchas intact (entry-point flag, entitlements⊆profile,
  user-enabled, /Applications via `make install`, real codesign).
- **Operational:** the Mac went to the **lock screen** during the Phase-2 run;
  the gate's load-bearing evidence was read directly from the live mount
  (identical regardless of GUI lock), but the GUI-driven Phase-3 gate (edit in
  app → re-read in Terminal) needs the screen unlocked + kept awake.

## 2026-06-15 — Phase 1 (M0+M1): Local SQLite wiki — DONE ✅ (gate passed)

A usable standalone Markdown wiki, persisted in SQLite, verified on the running
app (not just a green build). Branch `phase-1-local-wiki` (stacked off `main`,
unmerged — review locally; the pipeline keeps `main` pristine and stacks each
phase branch on the prior).

**Added**
- `Sources/WikiFSCore/` — new **library** target (so the store is unit-testable
  now and the read surface is reusable by the Phase-2 extension):
  - `SQLiteWikiStore.swift` — hand-wrapped system `SQLite3` (no third-party
    dep). `READWRITE|CREATE|FULLMUTEX`; pragmas `journal_mode=WAL` (return row
    asserted == `wal`) / `foreign_keys=ON` / `busy_timeout=5000`;
    `user_version`-guarded idempotent bootstrap of `pages`+`attachments`+
    `page_links` + unique slug index; statement cache; **`SQLITE_TRANSIENT`**
    text binding (not STATIC); slug collision suffix `-<first6 of ULID>`.
  - `ULID.swift` (48-bit ms ‖ 80 random bits, Crockford base32 — lexical sort
    == creation order, for cheap Phase-4 by-date views), `PageID`, `WikiPage`,
    `WikiPageSummary`, `WikiStore`(+`WikiStoreError`), `DatabaseLocation`,
    `WikiStoreModel`.
  - `WikiStoreModel.swift` — `@MainActor @Observable`. `summaries` always
    rebuilt from `store.listPages()` (never patched — SWIFTUI-RULES §3.1); live
    `draftTitle`/`draftBody` buffers (drafts live in the model so flush can read
    them — §3.5); 500 ms debounced autosave; `save()` reads live values at fire
    time and writes to the *loaded* page (correct even after selection advances);
    `flushPendingSave()` on page-switch and on app backgrounding.
- `Sources/WikiFS/` UI: `SidebarView` (List, +New, rename, delete via
  contextMenu **and** swipeActions), `PageDetailView` (title + `TextEditor` +
  live preview), `MarkdownPreview` (`AttributedString(markdown:)`, inline-only
  per INITIAL §4), `PageEditorMetrics`; `ContentView` rewired to
  `NavigationSplitView` + `ContentUnavailableView` empty state; `WikiFSApp`
  flushes autosave on `scenePhase != .active`. Spike files kept (Phase-2 ref),
  unhosted.
- `Tests/WikiFSTests/` — 10 tests incl. the §3.5/§9.4 stale-snapshot autosave
  regression and persistence-across-reopen.

**Decisions**
- **DB at `~/Library/Application Support/WikiFS/WikiFS.sqlite` for Phase 1**
  (option c), path injected via `DatabaseLocation`. The App Group container API
  (`containerURL(forSecurityApplicationGroupIdentifier:)`) returns `nil`
  without the sandbox + app-groups entitlement, and enabling the sandbox now
  would front-load the Phase-4 `Process`/agent-spawn restriction for zero
  Phase-1 benefit. **Phase 2 must repoint to the App Group container + run a
  one-time `migrate(from:to:)`** (hook noted in `DatabaseLocation.swift`). No
  entitlement/sandbox change this phase.
- Split `WikiFSCore` library (vs. `@testable import` of an executable) — clean
  testability + a shared store surface for the Phase-2 reader.
- Hand-wrapped SQLite3, no GRDB (dependency-free default honored).

**Verified (independent computer-use gate, fresh `make clean && make`)**
- Live preview: unique sentinel `VERIFY-7Q4Z` typed → preview rendered bold/
  italic live (screenshot read back, not just asserted).
- Persistence: clean-DB start → create `Home` → quit → relaunch → `Home` + body
  reload from disk. Running binary confirmed to be the fresh `build/` copy
  (`lsof`), alive 4 s past launch (no constraint crash).
- Data layer: `sqlite3 … "select … from pages"` → exactly one `Home` row with
  the exact sentinel body; DB at the literal Application Support path (no
  sandbox redirect). `make test` → 10/10 pass.

**Notes / caveats**
- Synthetic keystrokes don't reach SwiftUI `TextEditor`; the gate drove text via
  the AX `value` API (fires `.onChange` → autosave). Real user typing is
  unaffected. A bug found *by* the live gate — sidebar `List(selection:)` wrote
  the property directly, bypassing the load path — was fixed (`.onChange(of:
  selection)` → `handleSelectionChange`) with a regression test.
- Context-menu Rename / swipe-Delete are implemented + unit-tested but not
  visually gate-confirmed (outside the acceptance bar).
- DB state for Phase 2: fresh DB holds one clean `Home`; the pre-gate DB is
  preserved as `WikiFS.sqlite.verifier-bak` in the same dir.

## 2026-06-15 — File Provider spike PROVEN end to end ✅

De-risked the riskiest part of the project before Phase 1. A real
`NSFileProviderReplicatedExtension` (SwiftPM, no Xcode project), serving a
static tree, is mounted and readable from Terminal:
`cd ~/Library/CloudStorage/WikiFS-WikiFS && find . && cat README.md && grep -R …`
all work. Full writeup + the five gotchas: `plans/file-provider.md`.

**Added (spike code — kept as the Phase 2 reference, serves static content):**
- `Sources/WikiFSFileProvider/` — extension (`FileProviderExtension`,
  `WikiFSEnumerator`, `WikiFSItem`, `Catalog`, `main.swift`).
- `Sources/WikiFS/FileProviderSpike.swift` + `WelcomeView.swift` — register the
  domain, resolve the user-visible path, reveal/copy it.
- `WikiFS/WikiFSFileProvider.entitlements`; second SwiftPM target in
  `Package.swift`; `build.sh` now assembles + inside-out-signs the `.appex`.

**Five gotchas solved (each cost time — see plans/file-provider.md):**
1. Entitlements must be ⊆ the profile — claiming `get-task-allow` (which these
   profiles lack) → AMFI SIGKILL at exec, no crash log.
2. Mach-O entry must be `_NSExtensionMain` via `-e` linker flag; a Swift
   `main()` calling `NSExtensionMain()` recurses → SIGSEGV.
3. Third-party File Provider must be user-enabled in System Settings (consent
   gate); `EnabledByDefault` doesn't bypass it.
4. App must be in `/Applications` + launched once for `pluginkit` discovery →
   dev loop is `make install`.
5. First codesign with a fresh cert needs a one-time keychain approval
   (errSecInternalComponent until then).

**Verified strings/tools:** mount at `~/Library/CloudStorage/WikiFS-WikiFS`;
`fileproviderctl dump` + `pluginkit -m` + `.ips` backtraces were the usable
diagnostics (sandboxed shell can't read the unified log).

## 2026-06-15 — Apple provisioning done up front (pre-Phase 2)

Per the user's call, knocked out the File Provider / App Group portal setup
*before* starting feature work, to de-risk Phase 2. Full detail + verified
strings in `plans/signing.md`.

- Apple Development cert installed: `Apple Development: Thomas Ptacek
  (7F2QE7P59D)` — already matches `DEV_IDENTITY` in the `Makefile`.
- This Mac registered as a dev device (`00006050-00190839016B401C`).
- App IDs created: `org.sockpuppet.WikiFS`, `org.sockpuppet.WikiFS.FileProvider`
  (both with App Groups capability).
- **App Group is `group.org.sockpuppet.wiki`** — NOT `…wikifs`. The `…wikifs`
  group got fouled up in the portal; adopted the working `…wiki` name rather
  than redo + regenerate profiles. Docs updated to match. DB will live at
  `~/Library/Group Containers/group.org.sockpuppet.wiki/WikiFS.sqlite`.
- Two macOS App Development profiles downloaded to `signing/` (gitignored),
  decoded + verified: team `KK7E9G89GW`, this device included, expire
  2027-06-15, authorize the exact entitlements recorded in `plans/signing.md`.
- Remaining signing work (embed profiles, inside-out codesign, `make install`
  loop) is wired in Phase 2.

## 2026-06-15 — Milestone 0: app skeleton on its legs

Bootstrapped the SwiftPM build environment from `Makefile.example` and got a
hello-world WikiFS SwiftUI app building, signing, and launching.

**Added**

- `Package.swift` — executable target `WikiFS`, macOS 14+, Swift tools 6.0.
- `Sources/WikiFS/WikiFSApp.swift` — `@main` App + `WindowGroup`.
- `Sources/WikiFS/ContentView.swift` — `NavigationSplitView` shell (foreshadows
  the sidebar/editor split).
- `Sources/WikiFS/WelcomeView.swift` — hello-world detail pane.
- `WikiFS/WikiFS.entitlements` — minimal (no sandbox yet).
- `scripts/make-icon.swift` — generates the app icon (white `books.vertical.fill`
  on a blue→indigo squircle) at all macOS sizes.
- `build.sh` — `swift build` → assemble `.app` → write `Info.plist` → codesign.
- `Makefile` — adapted from `Makefile.example` (Moves → WikiFS): app name,
  entitlements path, icon comment, notary profile `wikifs-notary`.
- `.gitignore` — `build/ .build/ dist/`.
- Docs: `PLAN.md` (index), `plans/build-environment.md` (build deep-dive).

**Verified**

- `make` builds `build/WikiFS.app` (debug, v0.0.0-dev). Dev cert not in this
  keychain → ad-hoc signature (expected; `make run` still works).
- `make check` compiles clean.
- Live gate (`SWIFTUI-RULES` §9.1): `make run` launches, window renders the
  native two-column layout with the books hero, process stays alive past the
  first display cycle. Screenshot confirmed the UI.

**Notes / decisions**

- Bundle id `org.sockpuppet.WikiFS`; min macOS 14 (matches `Makefile.example`).
- Ran the `swiftui-pro` skill on the sources (CLAUDE.md requirement). Only
  finding: one-type-per-file — extracted `WelcomeView` out of `ContentView.swift`.
- Toolchain present: Apple Swift 6.3.2, macOS 26.5 host.

**Next (Milestone 1 / setup)**

- Add a `WikiFSTests` target so `make test` does something.
- Begin SQLite store + page model (Milestone 0 deliverables in `plans/INITIAL.md`
  also include persistence; the build skeleton is done, the data layer is not).
