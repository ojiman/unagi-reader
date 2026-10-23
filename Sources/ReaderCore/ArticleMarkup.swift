import Foundation
import SwiftSoup

public struct BodyLink: Sendable, Codable, Equatable {
    public let location: Int
    public let length: Int
    public let url: String
    public init(location: Int, length: Int, url: String) { self.location = location; self.length = length; self.url = url }
}

/// An image of the feed's HTML, at a UTF-16 offset of its paragraph's text (decision 0066). A block with images and no text is a
/// paragraph without text, so the feed's blocks stay apart. Sizes are the feed's `width` / `height`, when it gives them.
public struct BodyImage: Sendable, Codable, Equatable {
    public let location: Int
    public let url: String
    public let width: Int?
    public let height: Int?
    public let link: String?
    public init(location: Int, url: String, width: Int? = nil, height: Int? = nil, link: String? = nil) {
        self.location = location; self.url = url; self.width = width; self.height = height; self.link = link
    }
    func at(_ location: Int) -> BodyImage { BodyImage(location: location, url: url, width: width, height: height, link: link) }
}

/// A run of text with a look of its own (decision 0066): `<strong>` / `<b>` and table headers, `<em>` / `<i>`, and `<code>` outside `<pre>`.
public struct BodyStyle: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable { case strong, emphasis, code }
    public let location: Int
    public let length: Int
    public let kind: Kind
    public init(location: Int, length: Int, kind: Kind) { self.location = location; self.length = length; self.kind = kind }
}

/// A block of the feed's HTML as native text. Every field after `quoteDepth` is nil when unused, so a plain paragraph is saved as before.
/// `heading` is 1–6; `listDepth` counts the enclosing lists (the marker, 「•」 or 「1.」, is part of `text`); `code` is a `<pre>` block;
/// `table` is a row whose cells are separated by tabs.
public struct BodyParagraph: Sendable, Codable, Equatable {
    public let text: String
    public let links: [BodyLink]
    public let quoteDepth: Int
    public let images: [BodyImage]?
    public let heading: Int?
    public let listDepth: Int?
    public let code: Bool?
    public let table: Bool?
    public let styles: [BodyStyle]?
    public init(text: String, links: [BodyLink] = [], quoteDepth: Int = 0, images: [BodyImage]? = nil, heading: Int? = nil,
                listDepth: Int? = nil, code: Bool? = nil, table: Bool? = nil, styles: [BodyStyle]? = nil) {
        self.text = text; self.links = links; self.quoteDepth = quoteDepth; self.images = images?.isEmpty == true ? nil : images
        self.heading = heading; self.listDepth = listDepth == 0 ? nil : listDepth; self.code = code == true ? true : nil
        self.table = table == true ? true : nil; self.styles = styles?.isEmpty == true ? nil : styles
    }
    /// The same block with another text (a translation): links and styles go, because their positions change; images stay at the
    /// start or the end.
    func with(text: String) -> BodyParagraph {
        let end = (text as NSString).length
        return BodyParagraph(text: text, quoteDepth: quoteDepth, images: images?.map { $0.at($0.location == 0 ? 0 : end) }, heading: heading,
                             listDepth: listDepth, code: code, table: table)
    }
    static func decode(_ data: Data?, matching text: String) -> [BodyParagraph]? {
        guard let data, let paragraphs = try? JSONDecoder().decode([BodyParagraph].self, from: data),
              paragraphs.map(\.text).joined(separator: "\n\n") == text else { return nil }
        return paragraphs
    }
    static func encode(_ paragraphs: [BodyParagraph]?) -> Data? { paragraphs.flatMap { try? JSONEncoder().encode($0) } }
    /// The saved paragraphs as values, whatever the order of their JSON keys; nil for no format or an unreadable one.
    static func values(_ data: Data?) -> [BodyParagraph]? { data.flatMap { try? JSONDecoder().decode([BodyParagraph].self, from: $0) } }
    /// Whether a body has images: one without text is still a body (a comic, a photo).
    static func hasImages(_ paragraphs: [BodyParagraph]?) -> Bool { paragraphs?.contains { $0.images != nil } == true }
}

// Convert HTML into native text metadata. No HTML renderer or resource loading is used.
enum ArticleMarkup {
    static func parse(_ html: String, base: URL) -> [BodyParagraph]? {
        guard let document = try? SwiftSoup.parse(html, base.absoluteString), let body = document.body() else { return nil }
        return render(body, base: base)
    }
    static func render(_ root: Element, base: URL) -> [BodyParagraph] {
        let writer = Writer()
        writer.visit(root, base: base)
        writer.flush()
        return writer.paragraphs
    }
    private final class Writer {
        var paragraphs: [BodyParagraph] = []
        var text = ""
        var links: [BodyLink] = []
        var styles: [BodyStyle] = []
        var quoteDepth = 0
        var preformattedParagraph = false
        var heading: Int?
        /// The enclosing lists: ordered or not, and the next number.
        var lists: [(ordered: Bool, next: Int)] = []
        /// The marker of a list item, put before its first paragraph.
        var marker: String?
        var tableDepth = 0
        var cell = 0
        var images: [BodyImage] = []
        func append(_ value: String, link: URL?) {
            let start = (text as NSString).length
            text += value
            guard let link, !value.isEmpty else { return }
            let length = (value as NSString).length
            if let prior = links.last, prior.url == link.absoluteString, prior.location + prior.length == start {
                links[links.count - 1] = BodyLink(location: prior.location, length: prior.length + length, url: prior.url)
            } else { links.append(BodyLink(location: start, length: length, url: link.absoluteString)) }
        }
        func flush() {
            let raw = text as NSString
            let trimmed = text.trimmingCharacters(in: preformattedParagraph ? .newlines : .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let range = raw.range(of: trimmed)
                let prefix = marker ?? ""
                let shift = (prefix as NSString).length
                func moved(_ location: Int, _ length: Int) -> NSRange? {
                    let intersection = NSIntersectionRange(NSRange(location: location, length: length), range)
                    guard intersection.length > 0 else { return nil }
                    return NSRange(location: intersection.location - range.location + shift, length: intersection.length)
                }
                let adjusted = links.compactMap { link in moved(link.location, link.length).map { BodyLink(location: $0.location, length: $0.length, url: link.url) } }
                let styled = styles.compactMap { style in moved(style.location, style.length).map { BodyStyle(location: $0.location, length: $0.length, kind: style.kind) } }
                let placed = images.map { $0.at(min(max(0, $0.location - range.location), range.length) + shift) }
                paragraphs.append(BodyParagraph(text: prefix + trimmed, links: adjusted, quoteDepth: quoteDepth, images: placed, heading: heading,
                                                listDepth: lists.count, code: preformattedParagraph, table: tableDepth > 0, styles: styled))
                marker = nil
            } else if !images.isEmpty {
                // A block of images only (a comic panel, a photo, a counter and a button) is a paragraph without text.
                paragraphs.append(BodyParagraph(text: "", quoteDepth: quoteDepth, images: images.map { $0.at(0) }, listDepth: lists.count,
                                                table: tableDepth > 0))
            }
            text = ""; links = []; images = []; styles = []
        }
        func visit(_ node: Node, base: URL, link: URL? = nil, preformatted: Bool = false, depth: Int = 0) {
            guard depth <= 128 else { return }
            if let node = node as? TextNode {
                append(preformatted ? node.getWholeText() : node.getWholeText().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression), link: link)
                return
            }
            guard let element = node as? Element else { return }
            let tag = element.tagName().lowercased()
            guard !["script", "style", "iframe", "form", "nav", "aside", "footer", "header", "noscript"].contains(tag),
                  !element.hasAttr("hidden"), (try? element.attr("aria-hidden")) != "true" else { return }
            let base = (try? element.attr("xml:base")).flatMap { ArticleURL.validated($0, relativeTo: base) } ?? base
            if tag == "br" { append("\n", link: link); return }
            if tag == "img" {
                // Only web images; nothing in the feed's HTML is run or read from the Mac.
                guard let source = try? element.attr("src"), let url = ArticleURL.validated(source, relativeTo: base) else { return }
                func size(_ name: String) -> Int? { (try? element.attr(name)).flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil } }
                images.append(BodyImage(location: (text as NSString).length, url: url.absoluteString, width: size("width"), height: size("height"),
                                        link: link?.absoluteString))
                return
            }
            let headingLevel = ["h1", "h2", "h3", "h4", "h5", "h6"].firstIndex(of: tag).map { $0 + 1 }
            let block = ["p", "pre", "div", "section", "article", "main", "li", "tr", "blockquote", "cite", "ul", "ol", "table"].contains(tag)
                || headingLevel != nil
            if block { flush() }
            let priorPreformatted = preformattedParagraph, priorHeading = heading
            if tag == "pre" { preformattedParagraph = true }
            if tag == "blockquote" { quoteDepth += 1 }
            if let headingLevel { heading = headingLevel }
            if tag == "ul" || tag == "ol" { lists.append((tag == "ol", (try? element.attr("start")).flatMap { Int($0) } ?? 1)) }
            if tag == "li", let list = lists.last {
                marker = list.ordered ? "\(list.next). " : (lists.count == 1 ? "• " : "◦ ")
                // Feed HTML is input: at the edge of the number range the number stays, rather than stopping the app or wrapping.
                let (next, overflow) = list.next.addingReportingOverflow(1)
                lists[lists.count - 1].next = overflow ? list.next : next
            }
            if tag == "table" { tableDepth += 1 }
            if tag == "tr" { cell = 0 }
            if tag == "td" || tag == "th" {
                if cell > 0 {
                    while text.last?.isWhitespace == true { text.removeLast() }
                    append("\t", link: nil)
                }
                cell += 1
            }
            let kind: BodyStyle.Kind? = switch tag {
            case "strong", "b", "th": .strong
            case "em", "i": .emphasis
            case "code" where !preformatted: .code
            default: nil
            }
            let start = (text as NSString).length
            let target = tag == "a" ? (try? element.attr("href")).flatMap { ArticleURL.link($0, relativeTo: base) } : link
            for child in element.getChildNodes() { visit(child, base: base, link: target, preformatted: preformatted || tag == "pre", depth: depth + 1) }
            if let kind, (text as NSString).length > start { styles.append(BodyStyle(location: start, length: (text as NSString).length - start, kind: kind)) }
            if block { flush() }
            preformattedParagraph = priorPreformatted
            heading = priorHeading
            if tag == "blockquote" { quoteDepth -= 1 }
            if tag == "ul" || tag == "ol" { lists.removeLast() }
            if tag == "table" { tableDepth -= 1 }
        }
    }
}
