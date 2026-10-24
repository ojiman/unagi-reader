import Foundation
import SwiftSoup

/// Finds the feed that a Web page announces with `<link rel="alternate" type="application/rss+xml" href="…">`,
/// so the address of a site can be added as well as the address of its feed (decision 0038).
public enum FeedDiscovery {
    private static let feedTypes: Set<String> = ["application/rss+xml", "application/atom+xml", "application/rdf+xml"]

    /// The first announced feed whose address is usable, or nil. A relative address is resolved against `baseURL`.
    /// A secure page never leads to plain `http://`. Nothing is fetched here.
    public static func feedURL(inHTML data: Data, baseURL: URL) -> URL? {
        guard let document = try? SwiftSoup.parse(String(decoding: data, as: UTF8.self), baseURL.absoluteString),
              let links = try? document.select("link[href]") else { return nil }
        for link in links {
            guard let rel = try? link.attr("rel"), let type = try? link.attr("type"), let href = try? link.attr("href"),
                  rel.lowercased().split(whereSeparator: \.isWhitespace).contains("alternate"),
                  feedTypes.contains(type.trimmingCharacters(in: .whitespaces).lowercased()),
                  !href.trimmingCharacters(in: .whitespaces).isEmpty,
                  let url = ArticleURL.validated(href, relativeTo: baseURL),
                  !(baseURL.scheme?.lowercased() == "https" && url.scheme?.lowercased() == "http") else { continue }
            return url
        }
        return nil
    }

    /// The site icon a page names with `<link rel="icon">`, or `apple-touch-icon` when it names none (#441). Of several sizes, the smallest
    /// of at least 32 px (an 18 pt row at 2×) is taken, then one without a size, then the largest smaller one. SVG is skipped: the image
    /// loader does not read it. A relative address is resolved against `baseURL`; a secure page never leads to plain `http://`.
    public static func iconURL(inHTML data: Data, baseURL: URL) -> URL? {
        guard let document = try? SwiftSoup.parse(String(decoding: data, as: UTF8.self), baseURL.absoluteString),
              let links = try? document.select("link[href]") else { return nil }
        var best: (rank: (Int, Int), url: URL)?
        for link in links {
            guard let rel = try? link.attr("rel"), let href = try? link.attr("href") else { continue }
            let tokens = rel.lowercased().split(whereSeparator: \.isWhitespace)
            let touch = tokens.contains { $0.hasPrefix("apple-touch-icon") }
            guard tokens.contains("icon") || touch,
                  (try? link.attr("type"))?.lowercased().contains("svg") != true,
                  let url = ArticleURL.validated(href, relativeTo: baseURL), !url.path.lowercased().hasSuffix(".svg"),
                  !(baseURL.scheme?.lowercased() == "https" && url.scheme?.lowercased() == "http") else { continue }
            let size = ((try? link.attr("sizes")) ?? "").lowercased().split(whereSeparator: \.isWhitespace)
                .compactMap { $0.split(separator: "x").first.flatMap { Int($0) } }.max()
            let fit = switch size { case .some(let size) where size >= 32: (0, size); case .some(let size): (2, -size); case nil: (1, 0) }
            let rank = (touch ? 1 : 0, fit.0 * 100_000 + fit.1)
            if best == nil || rank < best!.rank { best = (rank, url) }
        }
        return best?.url
    }
}
