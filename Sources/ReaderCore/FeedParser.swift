import Foundation

public struct ParsedFeed: Sendable {
    public let title: String
    public let sourceURL: URL
    public let entries: [ParsedEntry]
    public let skippedEntries: Int
    public let siteURL: URL?
    public let iconURL: URL?
    public init(title: String, sourceURL: URL, entries: [ParsedEntry], skippedEntries: Int, siteURL: URL? = nil, iconURL: URL? = nil) {
        self.title = title; self.sourceURL = sourceURL; self.entries = entries; self.skippedEntries = skippedEntries
        self.siteURL = siteURL; self.iconURL = iconURL
    }
}

public struct ParsedEntry: Sendable {
    public let sourceID: String
    public let title: String
    public let url: URL?
    public let summary: String
    public let body: String
    public let coverage: ContentCoverage
    public let publishedAt: Date?
    public let imageURL: URL?
    public let bodyParagraphs: [BodyParagraph]?
    public init(sourceID: String, title: String, url: URL?, summary: String, body: String, coverage: ContentCoverage, publishedAt: Date?, imageURL: URL? = nil, bodyParagraphs: [BodyParagraph]? = nil) {
        self.sourceID = sourceID; self.title = title; self.url = url; self.summary = summary; self.body = body
        self.coverage = coverage; self.publishedAt = publishedAt; self.imageURL = imageURL; self.bodyParagraphs = bodyParagraphs
    }
}

public enum FeedImportError: LocalizedError {
    case invalidURL, invalidXML, htmlPage, noFeedInPage, unsupported, tooLarge, entities, missingTitle
    public var errorDescription: String? {
        switch self {
        case .invalidURL: String(localized: "Enter an HTTP(S) URL without a username or password.", bundle: ReaderLocalization.bundle)
        case .invalidXML: String(localized: "The feed XML could not be read. There may be a problem with the source.", bundle: ReaderLocalization.bundle)
        case .htmlPage: String(localized: "This is a web page, not a feed. Enter the feed URL.", bundle: ReaderLocalization.bundle)
        case .noFeedInPage: String(localized: "No feed was found on this page. Enter the feed URL.", bundle: ReaderLocalization.bundle)
        case .unsupported: String(localized: "This is not an RSS 1.0, RSS 2.0 or Atom feed.", bundle: ReaderLocalization.bundle)
        case .tooLarge: String(localized: "Feeds must be within 2 MB, 64 levels and 5,000 articles.", bundle: ReaderLocalization.bundle)
        case .entities: String(localized: "XML containing a DTD or custom entities cannot be imported.", bundle: ReaderLocalization.bundle)
        case .missingTitle: String(localized: "Enter a subscription name.", bundle: ReaderLocalization.bundle)
        }
    }
}

public enum ArticleURL {
    // Article identity drops fragments; user-clicked links must retain them.
    public static func link(_ value: String, relativeTo base: URL? = nil) -> URL? {
        guard let validated = validated(value, relativeTo: base),
              let resolved = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: base)?.absoluteURL,
              var components = URLComponents(url: validated, resolvingAgainstBaseURL: true) else { return nil }
        components.percentEncodedFragment = URLComponents(url: resolved, resolvingAgainstBaseURL: true)?.percentEncodedFragment
        return components.url
    }
    /// `http://` becomes `https://`: the system does not let the app fetch plain `http://`, and most sites answer on https as well.
    /// An address with its own port is left as it is (the port was meant for http).
    public static func secured(_ url: URL) -> URL {
        guard url.scheme == "http", url.port == nil, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.scheme = "https"
        return parts.url ?? url
    }

    public static func validated(_ value: String, relativeTo base: URL? = nil) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: base)?.absoluteURL,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        parts.scheme = parts.scheme?.lowercased(); parts.host = host.lowercased()
        parts.fragment = nil
        return parts.url
    }
}

public enum FeedParser {
    public static func parse(_ data: Data, sourceURL: URL, baseURL: URL? = nil) throws -> ParsedFeed {
        guard data.count <= 2 * 1024 * 1024 else { throw FeedImportError.tooLarge }
        guard let source = ArticleURL.validated(sourceURL.absoluteString) else { throw FeedImportError.invalidURL }
        guard !looksLikeHTML(data) else { throw FeedImportError.htmlPage }
        guard !looksLikeJSON(data) else { throw FeedImportError.unsupported }
        do { return try parseDocument(data, source: source, baseURL: baseURL) }
        catch FeedImportError.invalidXML {
            // A control character that XML forbids is a common slip in real feeds; read the rest once more without it.
            guard let cleaned = removingForbiddenControlCharacters(data) else { throw FeedImportError.invalidXML }
            return try parseDocument(cleaned, source: source, baseURL: baseURL)
        }
    }

    private static func parseDocument(_ data: Data, source: URL, baseURL: URL?) throws -> ParsedFeed {
        guard !declaresDTD(data) else { throw FeedImportError.entities }
        let reader = FeedXMLReader(source: baseURL.flatMap { ArticleURL.validated($0.absoluteString) } ?? source)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = reader
        guard parser.parse(), reader.failure == nil else { throw reader.failure ?? FeedImportError.invalidXML }
        guard reader.format != nil, reader.sawContainer else { throw FeedImportError.unsupported }
        return ParsedFeed(title: reader.title.isEmpty ? (source.host ?? "") : reader.title,
                          sourceURL: source, entries: reader.entries, skippedEntries: reader.skipped, siteURL: reader.siteURL, iconURL: reader.iconURL ?? reader.logoURL)
    }

    /// The start of a document without the whitespace, comments and XML declaration that may come before the markup.
    private static func markupStart(_ data: Data) -> Substring { skippingProlog(Substring(String(decoding: data.prefix(1024), as: UTF8.self))) }

    private static func skippingProlog(_ text: Substring) -> Substring {
        var head = text
        while true {
            head = head.drop { $0 == "\u{FEFF}" || $0.isWhitespace }
            if head.hasPrefix("<?"), let end = head.range(of: "?>") { head = head[end.upperBound...] }
            else if head.hasPrefix("<!--"), let end = head.range(of: "-->") { head = head[end.upperBound...] }
            else { return head }
        }
    }

    /// A DTD can stand only before the root element; an article's HTML in CDATA may carry its own `<!DOCTYPE html>` (#440).
    /// The parser's declaration callbacks refuse an entity declaration that an encoding hides from this scan (#126).
    private static func declaresDTD(_ data: Data) -> Bool {
        // Strip NULs only for declaration detection, including UTF-16/32 input, whose byte order mark decodes to U+FFFD.
        // Never resolve a DTD.
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\0", with: "")
        let declaration = skippingProlog(Substring(text).drop { $0 == "\u{FFFD}" })
        return declaration.hasPrefix("<!DOCTYPE") || declaration.hasPrefix("<!ENTITY")
    }

    /// A web page (the address of a site, not of its feed) starts with an HTML doctype or tag.
    private static func looksLikeHTML(_ data: Data) -> Bool {
        let head = markupStart(data).lowercased()
        return head.hasPrefix("<!doctype html") || head.hasPrefix("<html")
    }

    /// JSON Feed is a format this app does not read.
    private static func looksLikeJSON(_ data: Data) -> Bool { markupStart(data).hasPrefix("{") }

    /// The bytes without the C0 controls XML 1.0 forbids, or nil when there are none or removing them is not safe:
    /// UTF-16 and UTF-32 use zero bytes for ordinary characters, and ISO-2022-JP uses ESC (0x1B) in its shift sequences.
    private static func removingForbiddenControlCharacters(_ data: Data) -> Data? {
        guard !data.prefix(4).contains(0), !data.starts(with: [0xFF, 0xFE]), !data.starts(with: [0xFE, 0xFF]) else { return nil }
        let forbidden: (UInt8) -> Bool = { $0 < 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D }
        guard data.contains(where: forbidden), !data.contains(0x1B) else { return nil }
        return Data(data.filter { !forbidden($0) })
    }
}

private final class FeedXMLReader: NSObject, XMLParserDelegate {
    static let atom = "http://www.w3.org/2005/Atom"
    static let rss1 = "http://purl.org/rss/1.0/"
    static let dc = "http://purl.org/dc/elements/1.1/"
    static let content = "http://purl.org/rss/1.0/modules/content/"
    struct Node {
        let name: String
        let namespace: String
        let base: URL
        let attributes: [String: String]
        var text = ""
        var markup = ""
    }
    var stack: [Node] = []
    var format: String?
    var sawContainer = false
    var title = ""
    var entries: [ParsedEntry] = []
    var skipped = 0
    var failure: FeedImportError?
    let source: URL
    var entryDepth: Int?
    var values: [String: String] = [:]
    var entryURL: URL?
    var entryBase: URL?
    var siteURL: URL?
    var iconURL: URL?
    var logoURL: URL?
    var entryImages: [Int: URL] = [:]
    var namespaces: [String: [String]] = [:]
    init(source: URL) { self.source = source }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let ns = namespaceURI ?? ""
        let inherited = stack.last?.base ?? source
        let base = attributes["xml:base"].flatMap { ArticleURL.validated($0, relativeTo: inherited) } ?? inherited
        stack.append(Node(name: name, namespace: ns, base: base, attributes: attributes))
        if stack.count > 64 { failure = .tooLarge; parser.abortParsing(); return }
        if stack.count == 1 {
            if name == "rss" && ns.isEmpty { format = "rss" }
            else if name == "RDF" && ns == "http://www.w3.org/1999/02/22-rdf-syntax-ns#" { format = "rdf" }
            else if name == "feed" && ns == Self.atom { format = "atom"; sawContainer = true }
        }
        if name == "channel", stack.count == 2, standard(ns) { sawContainer = true }
        let isEntry = (format == "atom" && name == "entry" && ns == Self.atom && stack.count == 2)
            || (format == "rss" && name == "item" && ns.isEmpty && stack.count == 3 && stack[1].name == "channel")
            || (format == "rdf" && name == "item" && ns == Self.rss1 && stack.count == 2)
        if isEntry {
            entryDepth = stack.count; values = [:]; entryURL = nil; entryBase = base; entryImages = [:]
            values["id"] = attributes.first { key, _ in
                let parts = key.split(separator: ":", maxSplits: 1)
                return parts.count == 2 && parts[1] == "about" && namespaces[String(parts[0])]?.last == "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
            }?.value
        }
        if let depth = entryDepth, stack.count == depth + 1, format == "atom", ns == Self.atom, name == "link",
           [nil, "alternate"].contains(attributes["rel"]), entryURL == nil, let href = attributes["href"] {
            entryURL = ArticleURL.validated(href, relativeTo: base)
        }
        if let depth = entryDepth {
            if stack.count == depth + 1 {
                if (name == "enclosure" && standard(ns) || name == "link" && ns == Self.atom && attributes["rel"] == "enclosure"),
                   attributes["type"]?.lowercased().hasPrefix("image/") == true { recordImage(attributes["url"] ?? attributes["href"], base: base, priority: 0) }
                if ns == "http://search.yahoo.com/mrss/" {
                    if name == "thumbnail" { recordImage(attributes["url"], base: base, priority: 2) }
                    if name == "content", attributes["medium"] == "image" || attributes["type"]?.hasPrefix("image/") == true || (attributes["medium"] == nil && attributes["type"] == nil) { recordImage(attributes["url"], base: base, priority: 1) }
                }
            }
        } else if format == "atom", stack.count == 2, ns == Self.atom, name == "link", [nil, "alternate"].contains(attributes["rel"]), siteURL == nil {
            siteURL = attributes["href"].flatMap { ArticleURL.validated($0, relativeTo: base) }
        }
    }
    private func recordImage(_ value: String?, base: URL, priority: Int) {
        guard entryImages[priority] == nil, let value, let url = ArticleURL.validated(value, relativeTo: base) else { return }
        entryImages[priority] = url
    }
    private func standard(_ ns: String) -> Bool {
        switch format { case "atom": ns == Self.atom; case "rdf": ns == Self.rss1; case "rss": ns.isEmpty; default: false }
    }
    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        namespaces[prefix, default: []].append(namespaceURI)
    }
    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) { _ = namespaces[prefix]?.popLast() }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !stack.isEmpty {
            stack[stack.count - 1].text += string
            stack[stack.count - 1].markup += Self.escape(string)
        }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: text) }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard let node = stack.last else { return }
        let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let depth = entryDepth {
            if stack.count == depth + 1 {
                if standard(node.namespace) {
                    switch name {
                    case "title": values["title"] = node.attributes["type"] == "html" ? PlainFeedText.convert(text) : text
                    case "guid", "id": values["id"] = text
                    case "description", "summary":
                        values["summary"] = text
                        values["summaryBase"] = node.base.absoluteString
                        if node.attributes["type"] == "xhtml" { values["summaryHTML"] = node.markup }
                        if format != "atom" || node.attributes["type"] == "html", let image = ImageMetadata.firstHTMLImage(text, base: node.base) { recordImage(image.absoluteString, base: node.base, priority: 4) }
                        if format == "atom" && node.attributes["type"] != "html" { values["summaryPlain"] = "true" }
                    case "content":
                        values["body"] = text
                        values["bodyBase"] = node.base.absoluteString
                        if node.attributes["type"] == "xhtml" { values["bodyHTML"] = node.markup }
                        if format != "atom" || node.attributes["type"] == "html", let image = ImageMetadata.firstHTMLImage(text, base: node.base) { recordImage(image.absoluteString, base: node.base, priority: 3) }
                        if format == "atom" && node.attributes["type"] != "html" { values["bodyPlain"] = "true" }
                    case "pubDate", "published": values["date"] = text
                    case "updated": values["updated"] = text
                    case "link": if format != "atom" { entryURL = ArticleURL.validated(text, relativeTo: node.base) }
                    default: break
                    }
                } else if node.namespace == Self.content && name == "encoded" {
                    values["body"] = text
                    values["bodyBase"] = node.base.absoluteString
                    if let image = ImageMetadata.firstHTMLImage(text, base: node.base) { recordImage(image.absoluteString, base: node.base, priority: 3) }
                }
                else if node.namespace == Self.dc && name == "date" { values["date"] = text }
                else if node.namespace == "http://www.hatena.ne.jp/info/xmlns#", name == "imageurl" {
                    recordImage(text, base: node.base, priority: -1)
                }
            } else if stack.count == depth {
                finishEntry()
                entryDepth = nil
                if entries.count + skipped > 5_000 { failure = .tooLarge; parser.abortParsing() }
            }
        } else if name == "title", standard(node.namespace),
                  (format == "atom" && stack.count == 2) || (stack.count == 3 && stack[1].name == "channel") {
            title = node.attributes["type"] == "html" ? PlainFeedText.convert(text) : text
        }
        if entryDepth == nil, standard(node.namespace) {
            if format == "atom", stack.count == 2 {
                if name == "icon" { iconURL = ArticleURL.validated(text, relativeTo: node.base) }
                if name == "logo" { logoURL = ArticleURL.validated(text, relativeTo: node.base) }
            } else if stack.count == 3, stack[1].name == "channel", name == "link", siteURL == nil { siteURL = ArticleURL.validated(text, relativeTo: node.base) }
            else if stack.count == 4, stack[1].name == "channel", stack[2].name == "image", name == "url" { iconURL = ArticleURL.validated(text, relativeTo: node.base) }
        }
        stack.removeLast()
        if !stack.isEmpty {
            stack[stack.count - 1].text += node.text
            if node.namespace == "http://www.w3.org/1999/xhtml" {
                let attrs = node.attributes.sorted { $0.key < $1.key }.map { " \($0.key)=\"\(Self.escape($0.value))\"" }.joined()
                let voidElement = ["img", "br", "hr", "input", "link", "meta", "area", "base", "embed", "param", "source", "track", "wbr"].contains(name)
                stack[stack.count - 1].markup += voidElement ? "<\(name)\(attrs)>" : "<\(name)\(attrs)>\(node.markup)</\(name)>"
            } else { stack[stack.count - 1].markup += node.markup }
            if ["p", "div", "br", "pre", "li"].contains(name) { stack[stack.count - 1].text += "\n" }
        }
    }
    private func finishEntry() {
        if entryURL == nil, let guid = values["id"] { entryURL = ArticleURL.validated(guid) }
        guard let identity = values["id"].flatMap({ $0.isEmpty ? nil : $0 }) ?? entryURL?.absoluteString else { skipped += 1; return }
        let summaryBase = values["summaryBase"].flatMap(URL.init(string:)) ?? entryBase ?? source
        let bodyBase = values["bodyBase"].flatMap(URL.init(string:)) ?? entryBase ?? source
        let summaryHTML = values["summaryHTML"] ?? (values["summaryPlain"] == "true" ? nil : values["summary"])
        let bodyHTML = values["bodyHTML"] ?? (values["bodyPlain"] == "true" ? nil : values["body"])
        let summaryParagraphs = summaryHTML.flatMap { ArticleMarkup.parse($0, base: summaryBase) }
        let bodyParagraphs = values["body"] == nil ? summaryParagraphs : bodyHTML.flatMap { ArticleMarkup.parse($0, base: bodyBase) }
        // The summary the list shows is text: the empty paragraphs of image blocks are left out.
        let summary = summaryParagraphs?.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n") ?? values["summary"] ?? ""
        let body = bodyParagraphs?.map(\.text).joined(separator: "\n\n") ?? values["body"] ?? summary
        if let html = values["bodyHTML"], let image = ImageMetadata.firstHTMLImage(html, base: bodyBase) { recordImage(image.absoluteString, base: bodyBase, priority: 3) }
        if let html = values["summaryHTML"], let image = ImageMetadata.firstHTMLImage(html, base: summaryBase) { recordImage(image.absoluteString, base: summaryBase, priority: 4) }
        entries.append(ParsedEntry(sourceID: identity, title: values["title"] ?? "", url: entryURL,
                                   summary: summary, body: body, coverage: values["body"] == nil ? .summaryOnly : .feedProvided,
                                   publishedAt: Self.date(values["date"] ?? values["updated"] ?? ""), imageURL: entryImages.sorted { $0.key < $1.key }.first?.value, bodyParagraphs: bodyParagraphs))
    }
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func date(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: string) { return date }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { failure = .entities; parser.abortParsing() }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { failure = .entities; parser.abortParsing() }
    func parser(_ parser: XMLParser, foundUnparsedEntityDeclarationWithName name: String, publicID: String?, systemID: String?, notationName: String?) { failure = .entities; parser.abortParsing() }
    func parser(_ parser: XMLParser, foundNotationDeclarationWithName name: String, publicID: String?, systemID: String?) { failure = .entities; parser.abortParsing() }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { nil }
}

// Display as SwiftUI Text, never execute feed HTML or load its resources.
enum PlainFeedText {
    static func convert(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>|</(?:p|div|li|pre|h[1-6])\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        let entities = ["&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&nbsp;": " "]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let range = Range(match.range(at: 1), in: text), let whole = Range(match.range, in: text) else { continue }
                let value = String(text[range]); let number = value.hasPrefix("x") ? UInt32(value.dropFirst(), radix: 16) : UInt32(value)
                if let number, let scalar = UnicodeScalar(number) { text.replaceSubrange(whole, with: String(scalar)) }
            }
        }
        return text.replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
