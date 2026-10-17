import Foundation

/// Writes the subscriptions as an OPML 2.0 file (decision 0063): one outline per folder holding its subscriptions, then the unfiled
/// subscriptions at the top level. Nothing is fetched. The import (`OPMLParser`) reads the file back to the same subscriptions and folders.
public enum OPMLWriter {
    public static func data(feeds: [OPMLFeed], createdAt: Date) -> Data {
        var lines = [#"<?xml version="1.0" encoding="UTF-8"?>"#, #"<opml version="2.0">"#, "  <head>",
                     "    <title>Unagi Reader</title>", "    <dateCreated>\(rfc822(createdAt))</dateCreated>", "  </head>", "  <body>"]
        let folders = Dictionary(grouping: feeds.filter { !$0.folder.isEmpty }, by: \.folder)
        for name in folders.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            lines.append(#"    <outline text="\#(escape(name))" title="\#(escape(name))">"#)
            for feed in folders[name] ?? [] { lines.append("      " + outline(feed)) }
            lines.append("    </outline>")
        }
        for feed in feeds where feed.folder.isEmpty { lines.append("    " + outline(feed)) }
        lines += ["  </body>", "</opml>", ""]
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// The suggested file name, with the day it was written.
    public static func fileName(at date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "Unagi Reader Subscriptions %04d-%02d-%02d.opml", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    private static func outline(_ feed: OPMLFeed) -> String {
        var attributes = [#"type="rss""#, #"text="\#(escape(feed.title))""#, #"title="\#(escape(feed.title))""#,
                          #"xmlUrl="\#(escape(feed.url.absoluteString))""#]
        if let site = feed.siteURL { attributes.append(#"htmlUrl="\#(escape(site.absoluteString))""#) }
        return "<outline " + attributes.joined(separator: " ") + "/>"
    }

    /// Escapes an attribute value. Characters that XML 1.0 does not allow at all are left out; line breaks and tabs are kept as references.
    static func escape(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            case "\n": result += "&#10;"
            case "\r": result += "&#13;"
            case "\t": result += "&#9;"
            default:
                let value = scalar.value
                if value < 0x20 || value == 0xFFFE || value == 0xFFFF { continue }
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static func rfc822(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }
}

extension ReaderStore {
    /// The subscriptions as the OPML file lists them: in the sidebar's order of names, each with its folder. A subscription without a
    /// usable address (none in a normal library) is left out. A pending reload runs first, so a list that failed to load again after a
    /// save is not written out of date; when that reload fails, the error is thrown and nothing is written.
    public func opmlFeeds() throws -> [OPMLFeed] {
        try reloadIfNeeded()
        return feeds.compactMap { feed in
            guard let address = feed.sourceURL, let url = ArticleURL.validated(address) else { return nil }
            return OPMLFeed(title: feed.title, url: url, siteURL: feed.siteURL.flatMap { ArticleURL.validated($0) }, folder: feed.folder)
        }
    }
}
