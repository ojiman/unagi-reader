import Foundation
import SwiftSoup

public struct BodyLink: Sendable, Codable, Equatable {
    public let location: Int
    public let length: Int
    public let url: String
    public init(location: Int, length: Int, url: String) { self.location = location; self.length = length; self.url = url }
}

/// An image of the feed's HTML, at a UTF-16 offset of its paragraph's text (decision 0066). `block` is an image whose own block had no
/// text: it stands on a line of its own. Sizes are the feed's `width` / `height`, when it gives them.
public struct BodyImage: Sendable, Codable, Equatable {
    public let location: Int
    public let url: String
    public let width: Int?
    public let height: Int?
    public let link: String?
    public let block: Bool
    public init(location: Int, url: String, width: Int? = nil, height: Int? = nil, link: String? = nil, block: Bool = false) {
        self.location = location; self.url = url; self.width = width; self.height = height; self.link = link; self.block = block
    }
    func at(_ location: Int, block: Bool? = nil) -> BodyImage {
        BodyImage(location: location, url: url, width: width, height: height, link: link, block: block ?? self.block)
    }
}

public struct BodyParagraph: Sendable, Codable, Equatable {
    public let text: String
    public let links: [BodyLink]
    public let quoteDepth: Int
    /// Nil when the paragraph has none, so a body without images is saved as before.
    public let images: [BodyImage]?
    public init(text: String, links: [BodyLink] = [], quoteDepth: Int = 0, images: [BodyImage]? = nil) {
        self.text = text; self.links = links; self.quoteDepth = quoteDepth; self.images = images?.isEmpty == true ? nil : images
    }
    static func decode(_ data: Data?, matching text: String) -> [BodyParagraph]? {
        guard let data, let paragraphs = try? JSONDecoder().decode([BodyParagraph].self, from: data),
              paragraphs.map(\.text).joined(separator: "\n\n") == text else { return nil }
        return paragraphs
    }
    static func encode(_ paragraphs: [BodyParagraph]?) -> Data? { paragraphs.flatMap { try? JSONEncoder().encode($0) } }
    /// The saved paragraphs as values, whatever the order of their JSON keys; nil for no format or an unreadable one.
    static func values(_ data: Data?) -> [BodyParagraph]? { data.flatMap { try? JSONDecoder().decode([BodyParagraph].self, from: $0) } }
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
        writer.finish()
        return writer.paragraphs
    }
    private final class Writer {
        var paragraphs: [BodyParagraph] = []
        var text = ""
        var links: [BodyLink] = []
        var quoteDepth = 0
        var preformattedParagraph = false
        var images: [BodyImage] = []
        /// Images of blocks without text: they open the next paragraph, or close the last one.
        var pending: [BodyImage] = []
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
                let adjusted = links.compactMap { link -> BodyLink? in
                    let intersection = NSIntersectionRange(NSRange(location: link.location, length: link.length), range)
                    guard intersection.length > 0 else { return nil }
                    return BodyLink(location: intersection.location - range.location, length: intersection.length, url: link.url)
                }
                let placed = images.map { $0.at(min(max(0, $0.location - range.location), range.length)) }
                paragraphs.append(BodyParagraph(text: trimmed, links: adjusted, quoteDepth: quoteDepth, images: pending + placed))
                pending = []
            } else {
                pending += images.map { $0.at(0, block: true) }
            }
            text = ""; links = []; images = []
        }
        func finish() {
            guard !pending.isEmpty, let last = paragraphs.last else { return }
            let end = (last.text as NSString).length
            paragraphs[paragraphs.count - 1] = BodyParagraph(text: last.text, links: last.links, quoteDepth: last.quoteDepth,
                                                             images: (last.images ?? []) + pending.map { $0.at(end) })
            pending = []
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
            let block = ["p", "pre", "div", "section", "article", "main", "h1", "h2", "h3", "h4", "h5", "h6", "li", "tr", "blockquote", "cite"].contains(tag)
            if block { flush() }
            let priorPreformatted = preformattedParagraph
            if tag == "pre" { preformattedParagraph = true }
            if tag == "blockquote" { quoteDepth += 1 }
            let target = tag == "a" ? (try? element.attr("href")).flatMap { ArticleURL.link($0, relativeTo: base) } : link
            for child in element.getChildNodes() { visit(child, base: base, link: target, preformatted: preformatted || tag == "pre", depth: depth + 1) }
            if block { flush() }
            preformattedParagraph = priorPreformatted
            if tag == "blockquote" { quoteDepth -= 1 }
        }
    }
}
