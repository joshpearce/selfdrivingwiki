import Foundation

/// Per-developer signing/runtime identifiers: the **App Group** the app + File
/// Provider extension share, and the extension's **bundle id**.
///
/// These used to be hardcoded to one developer's Apple Developer team. App
/// Groups and bundle ids are *globally unique* across App Store Connect, so
/// anyone who clones this repo must build against their OWN ids — they cannot
/// reuse the author's. To keep **zero per-user values in committed source**, the
/// values are resolved at runtime, first hit wins:
///
///  1. **Environment variable** — dev/test override; inherited by child processes.
///  2. **`Bundle.main` Info.plist key** — `build.sh` injects these into the
///     `.app` and `.appex` so the GUI app and the extension agree.
///  3. **Sidecar `wiki-identifiers.env` next to the executable** — covers
///     `wikictl`, a plain CLI with no Info.plist; `build.sh` drops the file
///     beside the binary (both in `build/` and in the app's `Contents/Helpers`).
///  4. **Compiled-in default** — so a fresh `swift build` / `swift test` works
///     with no signing setup at all.
///
/// `signing/setup.sh` provisions the ids against the cloner's account and writes
/// `signing/local.config`; `build.sh` reads that and propagates the values into
/// (2) and (3). See `plans/signing.md`.
public enum WikiIdentifiers {
    /// The App Group container both sides of the projection share
    /// (`~/Library/Group Containers/<appGroupID>/`). See ``DatabaseLocation``.
    public static let appGroupID = resolve(
        env: "WIKI_APP_GROUP_ID",
        infoKey: "WIKIAppGroupID",
        default: "group.org.sockpuppet.wiki")

    /// The File Provider extension's bundle id, used to query/repair its
    /// `pluginkit` registration. Must equal the `.appex`'s CFBundleIdentifier.
    public static let fileProviderID = resolve(
        env: "WIKI_FILE_PROVIDER_ID",
        infoKey: "WIKIFileProviderID",
        default: "org.sockpuppet.WikiFS.FileProvider")

    // MARK: - Resolution

    private static func resolve(env: String, infoKey: String, default fallback: String) -> String {
        if let v = ProcessInfo.processInfo.environment[env], !v.isEmpty { return v }
        if let v = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String, !v.isEmpty { return v }
        if let v = sidecar[env], !v.isEmpty { return v }
        return fallback
    }

    /// `KEY=VALUE` pairs parsed once from `wiki-identifiers.env`. The keys match
    /// the environment-variable names (e.g. `WIKI_APP_GROUP_ID`). Empty when the
    /// file is absent — i.e. for the `.app`/`.appex` (which use the Info.plist
    /// path) and for plain test runs.
    ///
    /// Two locations are checked, in order, relative to the running executable:
    /// `build/wikictl` reads it from its own directory (the Phase A gate copy);
    /// the bundled `Contents/Helpers/wikictl` reads it from `../Resources`
    /// (build.sh can't leave plain files in the code-only Helpers dir).
    private static let sidecar: [String: String] = {
        let exeDir: URL? = Bundle.main.executableURL?.deletingLastPathComponent()
            ?? CommandLine.arguments.first.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        guard let exeDir else { return [:] }
        let candidates = [
            exeDir.appendingPathComponent("wiki-identifiers.env"),
            exeDir.deletingLastPathComponent()
                .appendingPathComponent("Resources/wiki-identifiers.env"),
        ]
        guard let text = candidates.lazy
            .compactMap({ try? String(contentsOf: $0, encoding: .utf8) })
            .first
        else { return [:] }

        var out: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            out[key] = value
        }
        return out
    }()
}
