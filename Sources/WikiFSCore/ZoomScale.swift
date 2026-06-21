import CoreGraphics

/// Pure, stateless namespace for text-zoom arithmetic used by the reader and
/// editor surfaces.
///
/// All state lives in `@AppStorage` on the UI side; this type owns every
/// clamping and stepping calculation so the UI layer is dumb — it passes the
/// current value in and gets the next value out.
///
/// ```swift
/// // zoom in
/// readerZoom = ZoomScale.zoomedIn(readerZoom)
///
/// // zoom out
/// readerZoom = ZoomScale.zoomedOut(readerZoom)
///
/// // reset
/// readerZoom = ZoomScale.defaultScale
/// ```
public enum ZoomScale {

    // MARK: - Constants

    /// Smallest allowed zoom multiplier (50 % of nominal size).
    public static let minimum: CGFloat = 0.5

    /// Largest allowed zoom multiplier (300 % of nominal size).
    public static let maximum: CGFloat = 3.0

    /// The multiplier applied (or its reciprocal removed) on each zoom step.
    public static let stepFactor: CGFloat = 1.1

    /// The zoom that reproduces the current unscaled appearance (`1× = default`).
    public static let defaultScale: CGFloat = 1.0

    // MARK: - Clamping

    /// Returns `scale` clamped to `minimum...maximum`.
    public static func clamped(_ scale: CGFloat) -> CGFloat {
        min(maximum, max(minimum, scale))
    }

    // MARK: - Stepping

    /// Returns the next zoom-in value: `current × stepFactor`, clamped to bounds.
    public static func zoomedIn(_ current: CGFloat) -> CGFloat {
        clamped(current * stepFactor)
    }

    /// Returns the next zoom-out value: `current ÷ stepFactor`, clamped to bounds.
    public static func zoomedOut(_ current: CGFloat) -> CGFloat {
        clamped(current / stepFactor)
    }
}
