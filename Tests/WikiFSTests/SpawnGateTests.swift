import Foundation
import Testing
@testable import WikiFS

/// Tests for the shared `SpawnGate` guarantee: two `AgentLauncher` instances that
/// share a single `SpawnGate` serialize their spawns globally.
///
/// This is the core Step-3 property — Ask + Edit + ingest never generate at the
/// same time even though they run on different launchers. The suite has three tests:
///
/// 1. `sharedGateSerializesAcrossLaunchers` — the KEY invariant: A holds the slot,
///    B (on a different launcher but the SAME gate) must wait; A's release hands the
///    slot to B atomically.
/// 2. `independentGatesDoNotSerialize` — isolation/contrast: launchers with SEPARATE
///    default gates contend on independent queues and can both acquire concurrently.
/// 3. `cancelledWaiterOnSharedGateSelfRemoves` — safety: a waiter that is cancelled
///    while queued on a shared gate self-removes cleanly; the holder's subsequent
///    release finds no live waiters and frees the slot without a stale handoff.
///
/// The single-launcher slot tests remain in `AgentSpawnSlotTests.swift`.
@MainActor
struct SpawnGateTests {

    private func makeLauncher(gate: SpawnGate) -> AgentLauncher {
        let launcher = AgentLauncher(spawnGate: gate)
        launcher.resolveClaude = { .found(path: "/usr/bin/true") }
        return launcher
    }

    private func makeLauncher() -> AgentLauncher {
        let launcher = AgentLauncher()
        launcher.resolveClaude = { .found(path: "/usr/bin/true") }
        return launcher
    }

    // MARK: - Shared gate serializes across launcher instances

    /// The KEY Step-3 property: two launchers sharing one `SpawnGate` contend on
    /// the same FIFO queue.
    ///
    /// - A acquires the slot fast-path; `a.isRunning` is true.
    /// - B (on a separate launcher, same gate) enqueues as a waiter;
    ///   `b.spawnSlotWaiterCount` (which delegates to the shared gate) is 1,
    ///   `b.isRunning` is false — B has NOT generated yet.
    /// - A releases: the slot transfers atomically to B.
    /// - `b.isRunning` is now true, `a.isRunning` is false.
    ///
    /// This locks in the AC "only one generates at a time" across DIFFERENT
    /// launchers — the guarantee that Ask / Edit / ingest serialize globally.
    @Test func sharedGateSerializesAcrossLaunchers() async {
        let gate = SpawnGate()
        let a = makeLauncher(gate: gate)
        let b = makeLauncher(gate: gate)

        // A acquires the shared slot (fast path — no contention yet).
        let aAcquired = await a.awaitSpawnSlot()
        #expect(aAcquired)
        #expect(a.isRunning)

        // B races for the slot — gate is held, so B suspends as a waiter.
        let bTask = Task { await b.awaitSpawnSlot() }
        // Yield twice: first to let bTask start, second to let it register its
        // continuation in the gate's waiter queue (matching the pattern in
        // AgentSpawnSlotTests.secondRequestWaitsUntilFirstReleases).
        await Task.yield()
        await Task.yield()

        // B is queued. `b.spawnSlotWaiterCount` delegates to `gate.waiterCount`;
        // since A and B share the same gate instance, both see count == 1.
        #expect(b.spawnSlotWaiterCount == 1)
        #expect(!b.isRunning)

        // A releases: atomic handoff — gate hands the slot to B without a window
        // where the fast path could sneak in a third launcher.
        a.releaseSpawnSlot()
        let bAcquired = await bTask.value
        #expect(bAcquired)
        #expect(b.isRunning)
        // A's per-instance flag cleared by releaseSpawnSlot.
        #expect(!a.isRunning)

        b.releaseSpawnSlot()
        #expect(!b.isRunning)
    }

    // MARK: - Independent gates do not serialize

    /// Isolation / contrast proof: two launchers with SEPARATE default gates (each
    /// constructed via `AgentLauncher()`) contend on INDEPENDENT queues and can both
    /// hold the slot concurrently. Neither waits for the other.
    ///
    /// This ensures the shared-gate serialization is opt-in (via `init(spawnGate:)`)
    /// and that adding a second launcher with its own gate does not accidentally
    /// block an unrelated launcher.
    @Test func independentGatesDoNotSerialize() async {
        let a = makeLauncher()  // owns its own SpawnGate()
        let b = makeLauncher()  // owns a different, independent SpawnGate()

        // Both acquire their respective gates with no contention.
        let aAcquired = await a.awaitSpawnSlot()
        let bAcquired = await b.awaitSpawnSlot()

        #expect(aAcquired)
        #expect(bAcquired)
        #expect(a.isRunning)
        #expect(b.isRunning)
        // Neither waited for the other.
        #expect(a.spawnSlotWaiterCount == 0)
        #expect(b.spawnSlotWaiterCount == 0)

        a.releaseSpawnSlot()
        b.releaseSpawnSlot()
        #expect(!a.isRunning)
        #expect(!b.isRunning)
    }

    // MARK: - Cancelled waiter on shared gate self-removes

    /// A second launcher's `awaitSpawnSlot()` Task that is cancelled while queued
    /// behind the first launcher's held slot must:
    ///   - self-remove from the gate's waiter queue (count returns to 0),
    ///   - return false (B never acquired the slot),
    ///   - leave A's subsequent `releaseSpawnSlot` clean — no stale handoff.
    ///
    /// This mirrors `cancelledWaiterSelfRemovesAndDoesNotStealSlot` in
    /// `AgentSpawnSlotTests` but across two launchers on a shared gate.
    @Test func cancelledWaiterOnSharedGateSelfRemoves() async {
        let gate = SpawnGate()
        let a = makeLauncher(gate: gate)
        let b = makeLauncher(gate: gate)

        // A holds the slot.
        _ = await a.awaitSpawnSlot()
        #expect(a.isRunning)

        // B waits behind A on the shared gate.
        let bTask = Task<Bool, Never> { await b.awaitSpawnSlot() }
        await Task.yield()
        await Task.yield()
        #expect(b.spawnSlotWaiterCount == 1)

        // Cancel B's wait — the `onCancel` handler hops to the main actor,
        // removes B's waiter from the shared gate's queue, and resumes B's
        // continuation so `awaitSpawnSlot` returns false.
        bTask.cancel()
        let bAcquired = await bTask.value
        #expect(!bAcquired)          // cancelled before slot was granted
        #expect(!b.isRunning)        // B never set its own isRunning flag
        #expect(b.spawnSlotWaiterCount == 0)  // B removed itself from the shared queue

        // A releases cleanly: no live waiters, gate's `held` flag cleared.
        a.releaseSpawnSlot()
        #expect(!a.isRunning)
        // Direct gate check confirms the shared queue is empty after the release.
        #expect(gate.waiterCount == 0)
    }
}
