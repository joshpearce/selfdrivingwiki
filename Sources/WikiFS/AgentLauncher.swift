import Foundation
import Observation
import WikiFSCore

/// Runs the three `claude -p` operations — Ingest / Query / Lint — against the
/// currently-selected wiki, streaming combined stdout/stderr back into the app
/// (`plans/llm-wiki.md` Phase C). Generalizes the v0 agent launcher: instead of a
/// free-form shell command, it spawns a scoped `claude -p` invocation built by the
/// pure `OperationCommand.build(...)` seam.
///
/// Allowed because the app is **un-sandboxed** (`WikiFS/WikiFS.entitlements` — no
/// `com.apple.security.app-sandbox`); a sandboxed app could not `Process`-spawn.
///
/// `@MainActor @Observable`: the view binds `output`, `isRunning`, `exitStatus`,
/// and `preflightError`. Output is appended on the main actor from the pipe
/// `readabilityHandler`s — we NEVER block on `waitUntilExit`; completion arrives
/// via `terminationHandler`, which is also where the per-wiki edit lock releases.
@MainActor
@Observable
final class AgentLauncher {
    /// Combined stdout+stderr captured so far for the current/last run.
    private(set) var output = ""
    /// True while a spawned `claude -p` process is running.
    private(set) var isRunning = false
    /// Exit status of the last finished process, or nil if none finished / one is
    /// running.
    private(set) var exitStatus: Int32?
    /// Set when the PATH preflight fails (claude not resolvable); shown in the UI
    /// instead of spawning. Cleared on the next successful run.
    private(set) var preflightError: String?
    /// The kind of the operation currently running (drives the UI title / spinner).
    private(set) var runningKind: WikiOperation.Kind?

    /// Builds the login-shell PATH-resolved `claude` path. Injected so tests can
    /// stub it; the app uses the real login-shell preflight.
    @ObservationIgnored var resolveClaude: () -> PathPreflight.Result = {
        PathPreflight.resolveOnLoginShell(executable: "claude")
    }

    private var process: Process?

    /// Run `operation` against one wiki. No-op if a process is already running.
    ///
    /// - `wikiID`/`wikiRoot`/`systemPrompt` come from the active wiki at click time
    ///   (`wikiRoot` resolved from the FP manager — never hardcoded).
    /// - `wikictlDirectory` is the dir holding the embedded `wikictl`
    ///   (`WikiFS.app/Contents/Helpers`), prepended to the child's PATH so the
    ///   agent's `wikictl` calls resolve.
    /// - `onLock`/`onUnlock` are the edit-lock callbacks: `onLock` fires before the
    ///   spawn, `onUnlock` from the `terminationHandler` (so a killed agent still
    ///   releases). Both run on the main actor.
    func run(
        operation: WikiOperation,
        wikiID: String,
        wikiRoot: String,
        systemPrompt: String,
        wikictlDirectory: String,
        onLock: @escaping @MainActor () -> Void,
        onUnlock: @escaping @MainActor @Sendable () -> Void
    ) {
        guard !isRunning else { return }

        // PATH preflight: surface a clear in-UI error instead of a cryptic spawn
        // failure if `claude` isn't on the login-shell PATH.
        let claudeExecutable: String
        switch resolveClaude() {
        case .found(let path):
            claudeExecutable = path
        case .missing(let reason):
            preflightError = reason
            output = ""
            exitStatus = nil
            return
        }
        preflightError = nil

        guard let scratch = makeScratchDirectory() else {
            preflightError = "Could not create a scratch working directory for the agent."
            return
        }

        let command = OperationCommand.build(
            operation: operation,
            wikiRoot: wikiRoot,
            wikiID: wikiID,
            systemPrompt: systemPrompt,
            scratchDirectory: scratch.path,
            wikictlDirectory: wikictlDirectory,
            claudeExecutable: claudeExecutable
        )

        output = ""
        exitStatus = nil
        isRunning = true
        runningKind = operation.kind
        onLock()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = scratch

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Stream both pipes onto the main actor as bytes arrive. Non-blocking: the
        // handlers fire on a background queue, then hop to the main actor.
        let appendHandler: @Sendable (FileHandle) -> Void = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.output.append(text) }
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = appendHandler
        stderrPipe.fileHandleForReading.readabilityHandler = appendHandler

        process.terminationHandler = { [weak self] proc in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            let status = proc.terminationStatus
            // Clean up the per-run scratch dir; best-effort.
            try? FileManager.default.removeItem(at: scratch)
            Task { @MainActor [weak self] in
                self?.isRunning = false
                self?.exitStatus = status
                self?.runningKind = nil
                self?.process = nil
                onUnlock()
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            output.append("Failed to launch: \(error.localizedDescription)\n")
            isRunning = false
            runningKind = nil
            try? FileManager.default.removeItem(at: scratch)
            onUnlock()
        }
    }

    /// Terminate the running process, if any. The `terminationHandler` releases the
    /// edit lock and clears `isRunning`.
    func stop() {
        process?.terminate()
    }

    /// Create a fresh per-run writable scratch dir under the app's Caches (decision
    /// #4 — Claude Code needs a writable cwd; the mount is read-only). Returns nil
    /// only if the directory can't be created.
    private func makeScratchDirectory() -> URL? {
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let scratch = base
            .appendingPathComponent("WikiFS-agent", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            return scratch
        } catch {
            return nil
        }
    }
}
