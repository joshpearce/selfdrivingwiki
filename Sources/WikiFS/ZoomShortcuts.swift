import SwiftUI
import WikiFSCore

/// Injects four invisible keyboard-shortcut buttons that mutate a zoom scale
/// binding using Safari-parity chords:
///
/// - ⌘+  zoom in
/// - ⌘=  zoom in  (same key as ⌘+ without Shift — matches Safari)
/// - ⌘−  zoom out
/// - ⌘0  reset to default
///
/// The buttons are rendered as a zero-size overlay so they never affect layout
/// or appearance. Attach this modifier only to the subtree that should own the
/// chord (reader subtree → reader zoom; editor subtree → editor zoom).
///
/// ```swift
/// TextEditor(...)
///     .zoomShortcuts($editorZoom)
///
/// MarkdownPreview(...)
///     .zoomShortcuts($readerZoom)
/// ```
extension View {
    func zoomShortcuts(_ scale: Binding<Double>) -> some View {
        self.overlay(ZoomShortcutButtons(scale: scale).frame(width: 0, height: 0))
    }
}

// MARK: - Private implementation

/// Four hidden buttons that own the zoom keyboard shortcuts.
///
/// Placed in a zero-size frame so they never occupy layout space. Each button
/// is additionally `.hidden()` and `.accessibilityHidden(true)` so it is
/// invisible and not announced to VoiceOver. SwiftUI still routes `.keyboardShortcut`
/// events to hidden buttons as long as they are in the view hierarchy.
private struct ZoomShortcutButtons: View {
    @Binding var scale: Double

    var body: some View {
        // Group keeps the four buttons as a single opaque View while remaining
        // transparent to layout — each button is individually .hidden() and
        // .accessibilityHidden so it never renders or is announced.
        Group {
            // ⌘+ — zoom in (requires Shift on most keyboards)
            Button("Zoom In") { zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)

            // ⌘= — zoom in without Shift (the physical key Safari uses)
            Button("Zoom In") { zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)

            // ⌘− — zoom out
            Button("Zoom Out") { zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)

            // ⌘0 — reset
            Button("Reset Zoom") { reset() }
                .keyboardShortcut("0", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        }
    }

    // MARK: - Actions (convert at the Double/CGFloat boundary here)

    private func zoomIn() {
        scale = Double(ZoomScale.zoomedIn(CGFloat(scale)))
    }

    private func zoomOut() {
        scale = Double(ZoomScale.zoomedOut(CGFloat(scale)))
    }

    private func reset() {
        scale = Double(ZoomScale.defaultScale)
    }
}
