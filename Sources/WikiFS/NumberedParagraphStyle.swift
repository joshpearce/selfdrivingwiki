import SwiftUI
import Textual
import WikiFSCore

/// A `ParagraphStyle` that applies `.id("p\(n)")` to each paragraph in document
/// order, so `ScrollViewReader.scrollTo("p3")` can target the third paragraph.
///
/// Headings already carry `.id(slug)` from Textual's `Heading.swift:24` — this
/// style is only needed for paragraph-level quote-scroll (§3 of markdown-anchors).
///
/// Call `NumberedParagraphStyle.resetCounter()` before the `StructuredText` renders
/// (e.g. in `.task(id:)`) to restart numbering at 1. All `makeBody` calls happen
/// on `@MainActor`, so the counter is safe without a lock.
@MainActor
struct NumberedParagraphStyle: StructuredText.ParagraphStyle {
    private nonisolated(unsafe) static var currentIndex: Int = 0

    /// Reset the paragraph counter. Call before `StructuredText` renders so the
    /// first paragraph gets `id("p1")`.
    static func resetCounter() {
        currentIndex = 0
    }

    func makeBody(configuration: Configuration) -> some View {
        Self.currentIndex += 1
        let index = Self.currentIndex
        return configuration.label
            .id("p\(index)")
            .textual.lineSpacing(.fontScaled(0.23))
            .textual.blockSpacing(.fontScaled(top: 0.8))
    }
}
