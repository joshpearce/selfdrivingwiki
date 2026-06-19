import Foundation

/// Thin wrapper around Apple's `NLEmbedding` (macOS 15). Produces a 512‑dim
/// Float32 BLOB from a text string, suitable for `vec_distance_cosine`.
///
/// The model is loaded lazily and guarded so that test/CI environments
/// (where `Bundle.main` is an .xctest, not an .app) never touch
/// NLEmbedding — avoiding potential framework-load crashes.
public enum EmbeddingService {

    private static var _model: Any?  // NLEmbedding? (opaque to avoid import)
    private static let lock = NSLock()

    private static func loadModel() -> Any? {
        lock.lock()
        defer { lock.unlock() }
        if _model != nil { return _model }
        // Never load in test/CI — the .app guard keeps us safe.
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return nil }
        guard #available(macOS 15, *) else { return nil }
        // Dynamic import: load NaturalLanguage only when needed.
        guard let cls = NSClassFromString("NLEmbedding") as? NSObject.Type else { return nil }
        let sel = NSSelectorFromString("sentenceEmbeddingForLanguage:")
        guard cls.responds(to: sel) else { return nil }
        let model = cls.perform(sel, with: "en")?.takeUnretainedValue()
        _model = model
        return model
    }

    // MARK: - Public

    /// Return a 512 × Float32 BLOB for `text`, or nil if the model is
    /// unavailable or the text cannot be embedded (e.g. empty / whitespace).
    public static func embeddingBlob(for text: String) -> Data? {
        guard let model = loadModel() else { return nil }
        // Call -[NLEmbedding vectorForString:] dynamically.
        guard model.responds(to: NSSelectorFromString("vectorForString:")) else { return nil }
        let doubles = model.perform(NSSelectorFromString("vectorForString:"), with: text)?
            .takeUnretainedValue() as? [Double]
        guard let doubles else { return nil }
        let floats = doubles.map { Float32($0) }
        return floats.withUnsafeBytes { Data($0) }
    }

    /// Convenience: embed the concatenated title + body of a page. Falls back
    /// to title-only if the body is empty. Returns nil if the resulting text
    /// cannot be embedded.
    public static func embeddingBlob(title: String, body: String) -> Data? {
        let text = body.isEmpty ? title : "\(title)\n\n\(body)"
        return embeddingBlob(for: text)
    }
}
