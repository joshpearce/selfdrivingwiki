import FileProvider
import Observation

/// Drives the File Provider spike from the app: register the domain, resolve
/// the user-visible Unix path (always asked of the system — never hardcoded),
/// and tear it down. Phase 4's real path button grows out of this.
@MainActor
@Observable
final class FileProviderSpike {
    private static let domain = NSFileProviderDomain(
        identifier: NSFileProviderDomainIdentifier(rawValue: "WikiFS"),
        displayName: "WikiFS"
    )

    var status = "Not registered"
    var path: String?

    /// Idempotent launch-time registration. Adding an already-registered domain
    /// must not crash, so we check the existing domains first and only add when
    /// ours is absent; any duplicate-add race is caught and ignored. Then we
    /// resolve the user-visible path.
    func registerIfNeeded() async {
        // Clean re-registration on launch: remove any existing domain (which
        // discards the daemon's cached/materialized tree) and add it fresh, so
        // the projection always reflects the current extension + SQLite content.
        // The projection is read-only and cheap to re-enumerate; Phase 3 will
        // replace this coarse refresh with fine-grained per-edit change
        // signaling. add() never crashes here because we removed first.
        if let existing = try? await NSFileProviderManager.domains() {
            for domain in existing where domain.identifier == Self.domain.identifier {
                // .removeAll discards the daemon's replicated/materialized tree
                // (a plain remove keeps it cached), so the re-add re-enumerates
                // cleanly from the SQLite-backed extension. No async variant of
                // this overload, so bridge the completion handler.
                _ = await withCheckedContinuation { continuation in
                    NSFileProviderManager.remove(domain, mode: .removeAll) { _, error in
                        continuation.resume(returning: error)
                    }
                }
            }
        }
        do {
            try await NSFileProviderManager.add(Self.domain)
            status = "Domain registered — resolving path…"
            await resolvePath()
        } catch {
            status = "add(domain): \(error.localizedDescription)"
            await resolvePath()
        }
    }

    func register() async {
        do {
            try await NSFileProviderManager.add(Self.domain)
            status = "Domain registered — resolving path…"
            await resolvePath()
        } catch {
            status = "add(domain) failed: \(error.localizedDescription)"
        }
    }

    func resolvePath() async {
        guard let manager = NSFileProviderManager(for: Self.domain) else {
            status = "No manager for domain"
            return
        }
        do {
            let url = try await manager.getUserVisibleURL(for: .rootContainer)
            path = url.path
            status = "Mounted"
        } catch {
            status = "getUserVisibleURL failed: \(error.localizedDescription)"
        }
    }

    func remove() async {
        do {
            try await NSFileProviderManager.remove(Self.domain)
            path = nil
            status = "Removed"
        } catch {
            status = "remove(domain) failed: \(error.localizedDescription)"
        }
    }
}
