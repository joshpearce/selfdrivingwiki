import CoreGraphics
import Testing
@testable import WikiFSCore

/// Tests for `ZoomScale` (reader-editor-zoom §1).
///
/// All floating-point comparisons use a tolerance; CGFloat arithmetic can
/// accumulate rounding error so exact equality is not asserted.
struct ZoomScaleTests {

    // MARK: - Tolerance helper

    /// Returns true when `a` and `b` differ by less than `eps`.
    private func isClose(_ a: CGFloat, _ b: CGFloat, eps: CGFloat = 1e-10) -> Bool {
        abs(a - b) < eps
    }

    // MARK: - Constants

    @Test func defaultScaleIsOne() {
        #expect(ZoomScale.defaultScale == 1.0)
    }

    // MARK: - Clamping

    @Test func clampedBelowMinimumReturnsMinimum() {
        #expect(ZoomScale.clamped(0.0) == ZoomScale.minimum)
        #expect(ZoomScale.clamped(-1.0) == ZoomScale.minimum)
        #expect(ZoomScale.clamped(0.49) == ZoomScale.minimum)
    }

    @Test func clampedAboveMaximumReturnsMaximum() {
        #expect(ZoomScale.clamped(10.0) == ZoomScale.maximum)
        #expect(ZoomScale.clamped(3.01) == ZoomScale.maximum)
    }

    @Test func clampedWithinRangeIsUnchanged() {
        let values: [CGFloat] = [0.5, 0.75, 1.0, 1.5, 2.0, 3.0]
        for v in values {
            #expect(ZoomScale.clamped(v) == v)
        }
    }

    @Test func clampedNonFiniteReturnsDefault() {
        // NaN and ±∞ cannot be ordered into the range and must never reach the
        // font math, so they coerce to a finite, in-range default.
        for value: CGFloat in [.nan, .infinity, -.infinity] {
            let result = ZoomScale.clamped(value)
            #expect(result == ZoomScale.defaultScale)
            #expect(result.isFinite)
            #expect(result >= ZoomScale.minimum && result <= ZoomScale.maximum)
        }
    }

    // MARK: - Stepping direction and magnitude

    @Test func zoomedInIncreasesValue() {
        let interior: CGFloat = 1.0
        #expect(ZoomScale.zoomedIn(interior) > interior)
    }

    @Test func zoomedOutDecreasesValue() {
        let interior: CGFloat = 1.0
        #expect(ZoomScale.zoomedOut(interior) < interior)
    }

    @Test func zoomedInAppliesStepFactor() {
        let start: CGFloat = 1.0
        let expected = (start * ZoomScale.stepFactor)
        #expect(isClose(ZoomScale.zoomedIn(start), expected))
    }

    @Test func zoomedOutAppliesStepFactor() {
        let start: CGFloat = 1.0
        let expected = (start / ZoomScale.stepFactor)
        #expect(isClose(ZoomScale.zoomedOut(start), expected))
    }

    // MARK: - Clamping at bounds during stepping

    @Test func zoomedInAtMaximumStaysAtMaximum() {
        #expect(ZoomScale.zoomedIn(ZoomScale.maximum) == ZoomScale.maximum)
    }

    @Test func zoomedInNearMaximumDoesNotExceedMaximum() {
        // One step below maximum — after zooming in the result must not exceed 3.0.
        let nearMax = ZoomScale.maximum / ZoomScale.stepFactor
        #expect(ZoomScale.zoomedIn(nearMax) <= ZoomScale.maximum)
    }

    @Test func zoomedOutAtMinimumStaysAtMinimum() {
        #expect(ZoomScale.zoomedOut(ZoomScale.minimum) == ZoomScale.minimum)
    }

    @Test func zoomedOutNearMinimumDoesNotGoBelowMinimum() {
        // One step above minimum — after zooming out the result must not go below 0.5.
        let nearMin = ZoomScale.minimum * ZoomScale.stepFactor
        #expect(ZoomScale.zoomedOut(nearMin) >= ZoomScale.minimum)
    }

    // MARK: - In / out symmetry

    @Test func zoomedInThenOutReturnsToStart() {
        // For any interior value, out(in(x)) should round-trip back to x.
        let interiorValues: [CGFloat] = [0.7, 1.0, 1.5, 2.0, 2.5]
        for start in interiorValues {
            let roundTripped = ZoomScale.zoomedOut(ZoomScale.zoomedIn(start))
            #expect(isClose(roundTripped, start),
                    "round-trip failed for \(start): got \(roundTripped)")
        }
    }
}
