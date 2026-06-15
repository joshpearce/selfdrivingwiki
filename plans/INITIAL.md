Here’s a project-plan shaped `PLAN.md`.

# WikiFS macOS App Plan

## Goal

Build a native macOS SwiftUI wiki app with a SQLite backend, Markdown editing/rendering, and a File Provider-backed filesystem projection so the wiki can be inspected by Unix tools and agents.

The core success criterion:

```sh
cd "$WIKI_PATH"
find .
cat pages/by-title/Some_Page.md
grep -R "some term" .
```

works from Terminal.app against the app’s wiki data.

## Non-goals

* Multi-user collaboration
* Cloud sync
* Rich block editing
* Full external write-back through the filesystem
* Git integration
* Fancy graph visualization
* Complex permissions
* iOS support

This is a local macOS app first.

---

# 1. Product Shape

## App Features

The app should provide:

* A page list/sidebar
* A basic Markdown text editor
* A rendered Markdown preview
* Create/rename/delete wiki pages
* SQLite persistence
* A File Provider domain exposing the wiki as files
* A button that reveals/copies a Unix filesystem path for Terminal verification

## UI Layout

Initial SwiftUI layout:

```text
+-------------------------------------------------------------+
| Sidebar                 | Editor / Preview                  |
|-------------------------+-----------------------------------|
| + New Page              | Title                             |
|                         |-----------------------------------|
| Pages                   | [ Markdown editor              ] |
| - Home                  | [                              ] |
| - File Provider Notes   | [                              ] |
| - Agent Interface       |-----------------------------------|
|                         | [ Rendered Markdown preview     ] |
|                         |                                   |
|-------------------------------------------------------------|
| [Expose Filesystem Path] [Copy Path] [Open Terminal]         |
+-------------------------------------------------------------+
```

## Basic Workflows

### Create Page

1. User clicks `New Page`.
2. App inserts page into SQLite.
3. Sidebar updates.
4. File Provider enumerator sees the new page.
5. Page appears under filesystem projection.

### Edit Page

1. User selects page.
2. App loads Markdown body from SQLite.
3. User edits in simple text editor.
4. App saves changes to SQLite.
5. App notifies File Provider that item changed.
6. Next filesystem read returns updated content.

### Verify Filesystem View

1. User clicks `Copy Unix Path`.
2. App obtains File Provider root URL or canonical item URL.
3. App copies path to clipboard.
4. User can run:

```sh
cd "$COPIED_PATH"
find .
cat pages/by-title/Home.md
```

---

# 2. Architecture

## Components

```text
WikiFS.app
  SwiftUI UI
  SQLite store
  Markdown renderer
  File Provider domain manager
  Agent launcher

WikiFSFileProvider.appex
  NSFileProviderReplicatedExtension
  Item metadata provider
  Directory enumerators
  Content fetcher
  Read-only filesystem projection
```

## Data Flow

```text
SwiftUI editor
    ↓
WikiStore
    ↓
SQLite database
    ↓
File Provider extension
    ↓
macOS filesystem projection
    ↓
Terminal / shell tools / agents
```

## Storage Principle

SQLite is the source of truth.

The File Provider view is a generated read-only projection of the SQLite wiki.

---

# 3. SQLite Backend

## Database Location

Use an app group container so both the main app and File Provider extension can access the database:

```text
~/Library/Group Containers/<team-id>.wikifs/WikiFS.sqlite
```

## Schema

Initial schema:

```sql
CREATE TABLE pages (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    slug TEXT NOT NULL,
    body_markdown TEXT NOT NULL DEFAULT '',
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    version INTEGER NOT NULL DEFAULT 1
);

CREATE UNIQUE INDEX pages_slug_unique ON pages(slug);

CREATE TABLE attachments (
    id TEXT PRIMARY KEY,
    page_id TEXT,
    filename TEXT NOT NULL,
    mime_type TEXT,
    data BLOB NOT NULL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    FOREIGN KEY(page_id) REFERENCES pages(id)
);

CREATE TABLE page_links (
    from_page_id TEXT NOT NULL,
    to_page_id TEXT NOT NULL,
    link_text TEXT NOT NULL,
    PRIMARY KEY (from_page_id, to_page_id),
    FOREIGN KEY(from_page_id) REFERENCES pages(id),
    FOREIGN KEY(to_page_id) REFERENCES pages(id)
);
```

## Store API

Define a small storage interface:

```swift
protocol WikiStore {
    func listPages() throws -> [WikiPageSummary]
    func getPage(id: PageID) throws -> WikiPage
    func createPage(title: String) throws -> WikiPage
    func updatePage(id: PageID, title: String, body: String) throws
    func deletePage(id: PageID) throws
}
```

The File Provider extension should depend on a read-only subset:

```swift
protocol WikiReadStore {
    func listFilesystemChildren(parent: WikiNodeID) throws -> [WikiNode]
    func metadata(for node: WikiNodeID) throws -> WikiNodeMetadata
    func contents(for node: WikiNodeID) throws -> Data
}
```

---

# 4. Markdown Editing and Rendering

## Editor

Start with the simplest possible editor:

```swift
TextEditor(text: $page.bodyMarkdown)
```

Use autosave with debounce:

* Save 300–750ms after typing stops.
* Save immediately on page switch.
* Save immediately on app backgrounding.

## Renderer

Use native Markdown support initially:

```swift
try AttributedString(markdown: page.bodyMarkdown)
```

Render preview with:

```swift
Text(attributedString)
```

Avoid building a full Markdown engine in v0.

## Page Links

Support wiki links later:

```markdown
[[Page Title]]
```

Initial v0 can ignore them or render as plain text.

v1 should parse wiki links and maintain `page_links`.

---

# 5. Filesystem Projection

## Projection Shape

Expose a deterministic, agent-friendly tree:

```text
WikiFS/
  README.md
  manifest.json
  pages/
    by-id/
      <page-id>.md
    by-title/
      Home--<short-id>.md
      Agent Interface--<short-id>.md
  attachments/
    by-id/
      <attachment-id>
  indexes/
    pages.jsonl
    links.jsonl
```

## Canonical Files

The canonical path for a page is:

```text
pages/by-id/<page-id>.md
```

The human-readable path is:

```text
pages/by-title/<escaped-title>--<short-id>.md
```

Both may expose the same page content.

## Generated Files

### `README.md`

Generated overview:

```markdown
# WikiFS

This is a read-only filesystem projection of the WikiFS database.

Useful paths:

- `pages/by-id/`
- `pages/by-title/`
- `indexes/pages.jsonl`
- `indexes/links.jsonl`
```

### `manifest.json`

Machine-readable summary:

```json
{
  "name": "WikiFS",
  "version": 1,
  "generated_at": "2026-06-15T00:00:00Z",
  "page_count": 123,
  "paths": {
    "pages_by_id": "pages/by-id",
    "pages_by_title": "pages/by-title",
    "page_index": "indexes/pages.jsonl"
  }
}
```

### `indexes/pages.jsonl`

One page per line:

```json
{"id":"...","title":"Home","path":"pages/by-id/....md","updated_at":...}
```

### `indexes/links.jsonl`

One link per line:

```json
{"from":"...","to":"...","link_text":"File Provider"}
```

## Filename Rules

Titles need deterministic escaping.

Rules:

* Normalize whitespace.
* Replace `/` with `∕` or `-`.
* Strip NUL and control characters.
* Avoid leading `.`.
* Avoid trailing spaces and periods.
* Append a short ID suffix to avoid collisions.

Example:

```text
File Provider / macOS?--01JABCDEF.md
```

---

# 6. File Provider Extension

## Extension Type

Use a replicated File Provider extension:

```text
NSFileProviderReplicatedExtension
```

The extension provides:

* Item metadata
* Directory enumeration
* File content materialization
* Change signaling

## Domain

Create one File Provider domain for the local wiki.

Potential domain identifier:

```text
com.example.wikifs.default
```

Display name:

```text
WikiFS
```

The app should register the domain on first launch.

## Item Identity

Use stable item identifiers.

Example virtual IDs:

```text
root
readme
manifest
pages
pages-by-id
pages-by-title
page-by-id:<page-id>
page-by-title:<page-id>
indexes
index-pages-jsonl
index-links-jsonl
attachments
attachment:<attachment-id>
```

Do not use paths as primary identity.

Paths are presentation.

## Item Metadata

Each item should provide:

* item identifier
* parent item identifier
* filename
* content type
* capabilities
* document size
* creation date
* modification date
* version

Pages should use:

```text
public.markdown
net.daringfireball.markdown
public.text
```

Generated JSON/JSONL files should use:

```text
public.json
public.text
```

## Read-only Capabilities

Expose files as read-only.

Allow:

* reading
* enumeration
* materialization

Reject:

* creation
* deletion
* rename
* modification
* reparenting

## Directory Enumeration

Implement enumerators for:

```text
root
pages
pages-by-id
pages-by-title
indexes
attachments
attachments-by-id
```

For large wikis, enumeration must be paginated.

## Content Fetching

When the system asks for content:

* For page files, render Markdown bytes from SQLite.
* For `manifest.json`, generate JSON.
* For `pages.jsonl`, stream or generate JSONL.
* For attachments, write attachment bytes to the provided file URL.
* For `README.md`, generate static Markdown.

Pseudo-flow:

```text
fetchContents(itemIdentifier)
  metadata = resolve itemIdentifier
  data = generate bytes from SQLite
  write data to provided temporary URL
  return file URL + item version
```

## Versioning

Use SQLite `version` and `updated_at`.

For pages:

```text
contentVersion = page.version
metadataVersion = hash(title, updated_at, version)
```

When a page changes, increment `version`.

Notify File Provider that the item changed.

---

# 7. Path Button

## Requirement

The app must have a button that gives the user a Unix path they can verify in Terminal.app.

Buttons:

```text
[Reveal Filesystem View]
[Copy Unix Path]
[Open Terminal Here]
```

## Behavior

### Copy Unix Path

1. Ensure File Provider domain is registered.
2. Ask `NSFileProviderManager` for a user-visible URL for the root or `pages` item.
3. Copy `url.path` to clipboard.
4. Show the path in the UI.

Example UI output:

```text
Filesystem path copied:

/Users/thomas/Library/CloudStorage/WikiFS
```

### Open Terminal Here

Optional v1 convenience:

```sh
open -a Terminal "$WIKI_PATH"
```

or launch Terminal with a command that `cd`s into the path.

## Verification Command

Show a copyable verification block:

```sh
cd "/path/from/app"
find .
cat README.md
cat pages/by-title/Home--*.md
```

---

# 8. Agent Integration

## Agent Contract

The app starts the agent with an environment variable:

```sh
WIKI_ROOT="/path/to/file-provider-root"
```

The agent should treat the wiki as read-only input.

Example launch:

```sh
WIKI_ROOT="/Users/thomas/Library/CloudStorage/WikiFS" \
agent analyze "$WIKI_ROOT"
```

## Agent-Friendly Files

Prioritize boring formats:

* Markdown for pages
* JSON for manifest
* JSONL for indexes
* Raw files for attachments

Avoid requiring the agent to understand app internals.

## Useful Generated Views

Add these after v0:

```text
indexes/
  pages.jsonl
  links.jsonl
  tags.jsonl
  backlinks.jsonl
  attachments.jsonl

pages/
  by-id/
  by-title/
  by-created-date/
  by-updated-date/
```

---

# 9. Milestones

## Milestone 0: App Skeleton

Deliverables:

* SwiftUI macOS app
* App group configured
* SQLite database opens from shared container
* Basic page model
* Create/list/select pages

Acceptance:

* User can create a page.
* Page persists across app restart.

## Milestone 1: Markdown Editor

Deliverables:

* Sidebar page list
* `TextEditor` for Markdown
* Preview pane
* Autosave
* Rename page

Acceptance:

* User can edit Markdown.
* Preview updates.
* Changes persist in SQLite.

## Milestone 2: File Provider Domain

Deliverables:

* File Provider extension target
* Domain registration from main app
* Root item
* Static `README.md`
* Static directories

Acceptance:

```sh
cd "$WIKI_PATH"
ls
cat README.md
```

works.

## Milestone 3: SQLite-backed Page Files

Deliverables:

* `pages/by-id`
* `pages/by-title`
* Page Markdown content fetched from SQLite
* Read-only capabilities
* Correct size and modification dates

Acceptance:

```sh
find "$WIKI_PATH/pages"
cat "$WIKI_PATH/pages/by-title/Home--"*.md
```

returns live wiki content.

## Milestone 4: Path Button

Deliverables:

* `Copy Unix Path` button
* visible path display
* verification commands shown in app
* optional `Open in Finder`

Acceptance:

* Clicking the button gives a path.
* Pasting that path into Terminal allows `cd`, `ls`, and `cat`.

## Milestone 5: Change Signaling

Deliverables:

* Page edits increment version.
* File Provider item changes are signaled.
* Terminal reads eventually see updated content.

Acceptance:

1. Open Terminal.
2. `cat pages/by-title/Home--*.md`
3. Edit Home in app.
4. Save.
5. `cat` again.
6. Updated text appears.

## Milestone 6: Agent Launch

Deliverables:

* App launches agent process.
* `WIKI_ROOT` passed in environment.
* Agent can traverse filesystem tree.
* App captures stdout/stderr.

Acceptance:

* Agent runs `find`, `cat`, or equivalent against the wiki path.
* Agent sees Markdown files.

---

# 10. Technical Risks

## File Provider Visibility

Need to verify where macOS places the domain and whether the root path is stable enough to pass to agents.

Mitigation:

* Never hardcode path.
* Always ask File Provider manager for the user-visible URL.
* Pass path dynamically when launching agents.

## Read-after-write Staleness

File Provider may cache materialized files.

Mitigation:

* Use explicit versions.
* Increment versions on every edit.
* Signal changed items.
* For agent launch, optionally force a small synchronization step first.

## Generated File Size

`getattr`-style metadata needs file sizes.

Mitigation:

* Cache generated byte sizes.
* Store page body byte length when saving.
* Generate JSONL indexes on demand and cache by database version.

## Filename Collisions

Multiple pages may share titles.

Mitigation:

* Use title plus short ID in human-readable paths.
* Keep stable canonical `by-id` paths.

## SQLite Access from Extension

Main app and extension may read the database concurrently.

Mitigation:

* Use SQLite WAL mode.
* Keep writes in main app.
* Let extension mostly read.
* Use short-lived read connections in extension.

Suggested pragmas:

```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;
```

---

# 11. Initial Implementation Order

1. Create macOS SwiftUI app.
2. Add app group.
3. Add SQLite wrapper.
4. Build page list + editor + preview.
5. Add File Provider extension target.
6. Register File Provider domain.
7. Expose static root with `README.md`.
8. Expose SQLite pages under `pages/by-id`.
9. Add `pages/by-title`.
10. Add `Copy Unix Path` button.
11. Verify in Terminal.
12. Add generated indexes.
13. Add agent launcher.

---

# 12. Definition of Done for v0

v0 is done when this works:

1. Launch app.
2. Create page named `Home`.
3. Type Markdown body.
4. Click `Copy Unix Path`.
5. Open Terminal.app.
6. Run:

```sh
cd "$COPIED_PATH"
find .
cat README.md
cat pages/by-title/Home--*.md
```

7. The page content appears as Markdown.
8. Edit the page in the app.
9. Re-run `cat`.
10. Updated content appears.

That is the whole point of v0.
