import Foundation

public enum FeedFetchResult: Sendable {
    case modified(ParsedFeed, etag: String?, lastModified: String?)
    case notModified
}

/// A feed that was fetched for a new subscription.
public struct FeedFetchOutcome: Sendable {
    public let parsed: ParsedFeed
    public let etag: String?
    public let lastModified: String?
    /// The Web page whose announced feed this is; nil when the address was the feed itself.
    public let foundOnPage: URL?
}

public struct FeedClient: Sendable {
    private let http: any HTTPFetching
    public init(http: any HTTPFetching = HTTPClient()) { self.http = http }

    /// `findsPageIcon`: the subscription has no icon yet, so a feed that names none takes the one its home page names (#441).
    public func fetch(url: URL, etag: String? = nil, lastModified: String? = nil, findsPageIcon: Bool = false) async throws -> FeedFetchResult {
        let response = try await load(url: url, etag: etag, lastModified: lastModified)
        if response.statusCode == 304 { return .notModified }
        var parsed = try parse(response, requestedURL: url)
        if findsPageIcon { parsed = await withPageIcon(parsed, page: nil) }
        return .modified(parsed, etag: response.headers["etag"], lastModified: response.headers["last-modified"])
    }

    /// For a new subscription: an address that is a Web page, not a feed, leads to the feed the page announces
    /// (one step: the announced address is read as a feed and is never searched again). A saved subscription is never
    /// redirected this way, so `fetch` does not do it. The page found gives the feed its icon; a feed address typed as it is waits for its first
    /// refresh, so the add sheet does not wait for another page.
    public func fetchOrDiscover(url: URL) async throws -> FeedFetchOutcome {
        let response = try await load(url: url, etag: nil, lastModified: nil)
        do {
            return FeedFetchOutcome(parsed: try parse(response, requestedURL: url), etag: response.headers["etag"],
                                    lastModified: response.headers["last-modified"], foundOnPage: nil)
        } catch FeedImportError.htmlPage {
            guard let feedURL = FeedDiscovery.feedURL(inHTML: response.data, baseURL: response.finalURL) else { throw FeedImportError.noFeedInPage }
            do {
                guard case .modified(let parsed, let etag, let modified) = try await fetch(url: feedURL) else { throw HTTPError.invalidResponse }
                return FeedFetchOutcome(parsed: await withPageIcon(parsed, page: response), etag: etag, lastModified: modified, foundOnPage: url)
            } catch FeedImportError.htmlPage { throw FeedImportError.noFeedInPage }
        }
    }

    /// The feed with the icon its site's home page names, or that page's `/favicon.ico` when it names none, so the page is not read
    /// again. A page that cannot be read leaves the feed as it is: it never stops the feed. `page` is the home page when it is in hand.
    private func withPageIcon(_ parsed: ParsedFeed, page: HTTPResponse?) async -> ParsedFeed {
        guard parsed.iconURL == nil, let home = parsed.siteURL.map(ArticleURL.secured) ?? URL(string: "/", relativeTo: parsed.sourceURL)?.absoluteURL else { return parsed }
        var response = page
        if response == nil {
            response = try? await http.fetch(url: home, headers: ["Accept": "text/html"], maximumBytes: 2 * 1024 * 1024)
        }
        guard let response, response.statusCode == 200, let base = ArticleURL.validated(response.finalURL.absoluteString),
              let icon = FeedDiscovery.iconURL(inHTML: response.data, baseURL: base) ?? URL(string: "/favicon.ico", relativeTo: base)?.absoluteURL
        else { return parsed }
        return ParsedFeed(title: parsed.title, sourceURL: parsed.sourceURL, entries: parsed.entries, skippedEntries: parsed.skippedEntries,
                          siteURL: parsed.siteURL, iconURL: icon)
    }

    private func load(url: URL, etag: String?, lastModified: String?) async throws -> HTTPResponse {
        var headers = ["Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml"]
        if let etag { headers["If-None-Match"] = etag }
        if let lastModified { headers["If-Modified-Since"] = lastModified }
        return try await http.fetch(url: url, headers: headers, maximumBytes: 2 * 1024 * 1024)
    }

    private func parse(_ response: HTTPResponse, requestedURL: URL) throws -> ParsedFeed {
        guard response.statusCode == 200 else { throw HTTPError.status(response.statusCode) }
        return try FeedParser.parse(response.data, sourceURL: requestedURL, baseURL: response.finalURL)
    }
}
