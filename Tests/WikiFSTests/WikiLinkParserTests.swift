import Testing
@testable import WikiFSCore

/// Unit tests for the pure `[[wiki-link]]` parser (INITIAL §4 v1).
struct WikiLinkParserTests {

    @Test func parsesSimpleLink() {
        let links = WikiLinkParser.parse("See [[Home]] for details.")
        #expect(links == [.init(target: "Home", linkText: "Home")])
    }

    @Test func parsesAliasedLink() {
        let links = WikiLinkParser.parse("See [[Home|the front page]].")
        #expect(links == [.init(target: "Home", linkText: "the front page")])
    }

    @Test func parsesMultipleLinks() {
        let links = WikiLinkParser.parse("[[Alpha]] then [[Beta|B]] then [[Gamma]]")
        #expect(links == [
            .init(target: "Alpha", linkText: "Alpha"),
            .init(target: "Beta", linkText: "B"),
            .init(target: "Gamma", linkText: "Gamma"),
        ])
    }

    @Test func dedupesByTargetFirstAliasWins() {
        let links = WikiLinkParser.parse("[[Home|first]] and again [[Home|second]] and [[Home]]")
        #expect(links == [.init(target: "Home", linkText: "first")])
    }

    @Test func skipsEmptyTargets() {
        #expect(WikiLinkParser.parse("[[]] and [[   ]] are empty").isEmpty)
    }

    @Test func collapsesAndTrimsWhitespaceInTarget() {
        let links = WikiLinkParser.parse("[[  Home   Page  ]]")
        #expect(links == [.init(target: "Home Page", linkText: "Home Page")])
    }

    @Test func emptyAliasFallsBackToTarget() {
        let links = WikiLinkParser.parse("[[Home|   ]]")
        #expect(links == [.init(target: "Home", linkText: "Home")])
    }

    @Test func ignoresUnmatchedBrackets() {
        // A single `[` / `]`, or an unterminated `[[`, is not a link.
        #expect(WikiLinkParser.parse("a [single] and an open [[unterminated link").isEmpty)
    }

    @Test func returnsEmptyForNoLinks() {
        #expect(WikiLinkParser.parse("just some plain markdown text").isEmpty)
    }

    // MARK: - source: prefix (Phase B)

    @Test func parsesSourcePrefixLink() {
        let links = WikiLinkParser.parse("See [[source:My Notes]].")
        #expect(links.count == 1)
        #expect(links[0].linkType == .source)
        #expect(links[0].target == "My Notes")
        #expect(links[0].linkText == "My Notes")
    }

    @Test func sourceLinkWithAliasPreservesAlias() {
        let links = WikiLinkParser.parse("[[source:My Notes|my notes]]")
        #expect(links[0].linkType == .source)
        #expect(links[0].target == "My Notes")
        #expect(links[0].linkText == "my notes")
    }

    @Test func sourcePrefixNormalizesRemainder() {
        let links = WikiLinkParser.parse("[[source:  X  ]]")
        #expect(links[0].target == "X") // no leading/trailing space
    }

    @Test func emptySourceTargetIsSkipped() {
        let links = WikiLinkParser.parse("[[source:]] and [[source:   ]]")
        #expect(links.isEmpty)
    }

    @Test func pagePrefixEscapesSourcePrefixTitle() {
        // A page literally titled "source:foo" is reachable via [[page:source:foo]].
        let links = WikiLinkParser.parse("[[page:source:foo]]")
        #expect(links[0].linkType == .page)
        #expect(links[0].target == "source:foo")
    }

    @Test func sourceAndPageLinksDedupSeparately() {
        let links = WikiLinkParser.parse("[[source:X|a]] [[source:X|b]] [[X]] [[source:X]]")
        #expect(links.count == 2) // one page link "X" + one source link "X"
        let sourceLink = links.first { $0.linkType == .source }
        #expect(sourceLink?.linkText == "a") // first alias wins
    }

    // MARK: - classify

    @Test func classifyDefaultsToPage() {
        let (kind, target) = WikiLinkParser.classify("Plain Title")
        #expect(kind == .page)
        #expect(target == "Plain Title")
    }

    @Test func classifySourcePrefix() {
        let (kind, target) = WikiLinkParser.classify("source:My Notes")
        #expect(kind == .source)
        #expect(target == "My Notes") // prefix stripped, remainder normalized
    }

    @Test func classifyPagePrefixTakesPrecedence() {
        let (kind, target) = WikiLinkParser.classify("page:source:foo")
        #expect(kind == .page)
        #expect(target == "source:foo")
    }

    @Test func classifyEmptySourceTargetFallsBackToPage() {
        // peel returns nil (rest is empty), so classify falls through → .page with
        // the original string. The parser's skip logic handles the empty-prefix case.
        let (kind, target) = WikiLinkParser.classify("source:")
        #expect(kind == .page)
        #expect(target == "source:")
    }
}
