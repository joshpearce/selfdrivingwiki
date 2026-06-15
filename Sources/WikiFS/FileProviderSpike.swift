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
