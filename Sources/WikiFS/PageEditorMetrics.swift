import CoreGraphics

/// Centralized layout constants for the Phase 1 editor surfaces
/// (SWIFTUI-RULES §2.4 — no scattered magic numbers).
enum PageEditorMetrics {
    static let sidebarMinWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 260
    static let detailMinWidth: CGFloat = 420

    /// Padding around the editor / preview content.
    static let contentInset: CGFloat = 20
    /// Vertical gap between the title field, the editor, and the preview.
    static let sectionSpacing: CGFloat = 12
    /// Minimum height for the markdown editor before the preview takes over.
    static let editorMinHeight: CGFloat = 160
    static let previewMinHeight: CGFloat = 120
    static let dividerOpacity: Double = 0.5
}
