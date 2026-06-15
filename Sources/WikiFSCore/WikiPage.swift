import Foundation

/// A full wiki page, mirroring the `pages` row in SQLite (INITIAL.md §3).
public struct WikiPage: Identifiable, Hashable, Sendable {
    public let id: PageID
    public var title: String
    public var slug: String
    public var bodyMarkdown: String
    public let createdAt: Date
    public var updatedAt: Date
    public var version: Int

    public init(
        id: PageID,
        title: String,
        slug: String,
        bodyMarkdown: String,
        createdAt: Date,
        updatedAt: Date,
        version: Int
    ) {
        self.id = id
        self.title = title
        self.slug = slug
        self.bodyMarkdown = bodyMarkdown
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
    }
}
