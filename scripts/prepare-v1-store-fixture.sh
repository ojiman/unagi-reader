#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
destination=${1:?Usage: prepare-v1-store-fixture.sh /private/tmp/unagi-reader-...}
python3 - "$destination" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]).resolve()
if p.parent != Path('/private/tmp') or not p.name.startswith('unagi-reader-'):
    raise SystemExit('Use a dedicated /private/tmp/unagi-reader-* directory')
if p.exists():
    raise SystemExit('Destination already exists; use a new fixture directory')
p.mkdir()
PY
source_dir=$(mktemp -d /private/tmp/unagi-reader-v1-source.XXXXXX)
baseline=${2:-53102cc42ea665b3379ad2a23d842c3186ad9c3e}
case "$baseline" in
    53102cc42ea665b3379ad2a23d842c3186ad9c3e|f9db83b49a82947a7031ddf874bc94fcb91ef89d|1007dce64ebc5d1c9d7ac6f0b3e05869c8581ba4|215b901ffc3863b3e1afd1e17a76b18101fc0cb6|52429b44c647a4a3ee2c95fb039bf99d5e674f18|ae8aa781856a586ab6fa10d17449e16fa0cddda8|60da7dff8ff3741afc0707652bedea256f9e83df|d37f41b9c72613f207c5fc2d3a59ef2485e23879) ;;
    *) echo "Use a tested baseline commit" >&2; exit 2 ;;
esac
git archive "$baseline" | tar -x -C "$source_dir"
# The baselines are old commits, whose app target is still called RSSReader (renamed to UnagiReader afterwards).
python3 - "$source_dir" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]) / 'Package.swift'
s = p.read_text()
for app in ('RSSReader', 'UnagiReader'):   # the app target had the first name in the old baselines and has the second since the rename
    s = s.replace('.executableTarget(name: "%s",' % app, '.executableTarget(name: "V1Fixture", dependencies: ["ReaderCore"]),\n        .executableTarget(name: "%s",' % app)
p.write_text(s)
PY
mkdir -p "$source_dir/Sources/V1Fixture"
cat > "$source_dir/Sources/V1Fixture/main.swift" <<'SWIFT'
import Foundation
import ReaderCore

@main struct V1Fixture {
    @MainActor static func main() throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let at = Date(timeIntervalSince1970: 1_791_152_000)
        let store = try ReaderStore(url: destination.appending(path: "Reader.store"), now: at)
        let xml = """
        <rss version="2.0"><channel><title>合成フィード</title><item><guid>synthetic-1</guid>
        <title>合成記事</title><link>https://synthetic.example/article/1</link>
        <description>合成RSS要約</description></item></channel></rss>
        """
        let feed = try store.importFeed(FeedParser.parse(Data(xml.utf8), sourceURL: URL(string: "https://synthetic.example/rss")!), receivedAt: at)
        try store.updateSubscription(feed, title: "合成購読", folder: "技術")
        let article = store.articles[0]
        try store.markDisplayed(articleID: article.id, at: at.addingTimeInterval(60))
        try store.applyRetention(days: 90, at: at)
        let note = try store.createNote(in: WeekCalendar.range(containing: at, timeZone: TimeZone(identifier: "Asia/Tokyo")!), title: "合成の週", at: at)
        try store.saveNote(id: note.id, text: "残す合成ノート", at: at)
        try store.adoptSources(noteID: note.id, articleIDs: [article.id])
        let period = store.weeks[0]
        let manifest: [String: Any] = [
            "baseline": "53102cc42ea665b3379ad2a23d842c3186ad9c3e", "at": at.timeIntervalSince1970,
            "feedID": feed.id.uuidString, "articleID": article.id.uuidString, "noteID": note.id.uuidString,
            "periodID": period.id.uuidString, "start": period.start.timeIntervalSince1970, "end": period.end.timeIntervalSince1970,
            "firstReadAt": at.addingTimeInterval(60).timeIntervalSince1970
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted])
            .write(to: destination.appending(path: "expected.json"))
    }
}
SWIFT
python3 - "$source_dir" "$baseline" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]) / 'Sources/V1Fixture/main.swift'
s = p.read_text().replace('53102cc42ea665b3379ad2a23d842c3186ad9c3e', sys.argv[2])
if sys.argv[2] in ('f9db83b49a82947a7031ddf874bc94fcb91ef89d', '1007dce64ebc5d1c9d7ac6f0b3e05869c8581ba4', '215b901ffc3863b3e1afd1e17a76b18101fc0cb6'):
    s = s.replace('let manifest: [String: Any]', 'var manifest: [String: Any]')
    s = s.replace('        try JSONSerialization.data', '''        try store.setStar(articleID: article.id, isStarred: true, at: at)
        let scrap = try store.scrap(articleID: article.id, at: at, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        manifest["dailyNoteID"] = scrap.noteID.uuidString
        manifest["scrapKey"] = scrap.key
        try JSONSerialization.data''')
p.write_text(s)
PY
if [ "$baseline" = "52429b44c647a4a3ee2c95fb039bf99d5e674f18" ]; then
cat > "$source_dir/Sources/V1Fixture/main.swift" <<'SWIFT'
import Foundation
import ReaderCore

// The store of the build that still had themes with goals, questions and answers (before decision 0019).
@main struct V1Fixture {
    @MainActor static func main() throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let at = Date(timeIntervalSince1970: 1_791_152_000)
        let store = try ReaderStore(url: destination.appending(path: "Reader.store"), now: at)
        let xml = """
        <rss version="2.0"><channel><title>合成フィード</title><item><guid>synthetic-1</guid>
        <title>合成記事</title><link>https://synthetic.example/article/1</link>
        <description>合成RSS要約</description></item></channel></rss>
        """
        let feed = try store.importFeed(FeedParser.parse(Data(xml.utf8), sourceURL: URL(string: "https://synthetic.example/rss")!), receivedAt: at)
        try store.updateSubscription(feed, title: "合成購読", folder: "技術")
        let article = store.articles[0]
        try store.markDisplayed(articleID: article.id, at: at.addingTimeInterval(60))
        try store.setStar(articleID: article.id, isStarred: true, at: at)
        let theme = try store.createTheme(name: "合成テーマ", goal: "合成ゴール", at: at)
        try store.addArticle(article.id, toTheme: theme.id, at: at)
        try store.saveNote(themeID: theme.id, text: "残す合成ノート", at: at)
        let question = try store.addQuestion(themeID: theme.id, lens: .custom, text: "合成の問い", at: at)
        try store.saveAnswer(questionID: question.id, answer: "合成の答え", at: at)
        let manifest: [String: Any] = [
            "baseline": "52429b44c647a4a3ee2c95fb039bf99d5e674f18", "at": at.timeIntervalSince1970,
            "feedID": feed.id.uuidString, "articleID": article.id.uuidString, "themeID": theme.id.uuidString,
            "firstReadAt": at.addingTimeInterval(60).timeIntervalSince1970
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted])
            .write(to: destination.appending(path: "expected.json"))
    }
}
SWIFT
fi
if [ "$baseline" = "ae8aa781856a586ab6fa10d17449e16fa0cddda8" ]; then
cat > "$source_dir/Sources/V1Fixture/main.swift" <<'SWIFT'
import Foundation
import ReaderCore

// The store of the build after S1a (themes with a name and a note, no goal, no questions), before the rename to notes.
@main struct V1Fixture {
    @MainActor static func main() throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let at = Date(timeIntervalSince1970: 1_791_152_000)
        let store = try ReaderStore(url: destination.appending(path: "Reader.store"), now: at)
        let xml = """
        <rss version="2.0"><channel><title>合成フィード</title><item><guid>synthetic-1</guid>
        <title>合成記事</title><link>https://synthetic.example/article/1</link>
        <description>合成RSS要約</description></item></channel></rss>
        """
        let feed = try store.importFeed(FeedParser.parse(Data(xml.utf8), sourceURL: URL(string: "https://synthetic.example/rss")!), receivedAt: at)
        try store.updateSubscription(feed, title: "合成購読", folder: "技術")
        let article = store.articles[0]
        try store.markDisplayed(articleID: article.id, at: at.addingTimeInterval(60))
        try store.setStar(articleID: article.id, isStarred: true, at: at)
        let theme = try store.createTheme(name: "合成テーマ", at: at)
        try store.addArticle(article.id, toTheme: theme.id, at: at)
        try store.saveNote(themeID: theme.id, text: "合成ノート", at: at)
        let manifest: [String: Any] = [
            "baseline": "ae8aa781856a586ab6fa10d17449e16fa0cddda8", "at": at.timeIntervalSince1970,
            "feedID": feed.id.uuidString, "articleID": article.id.uuidString, "themeID": theme.id.uuidString,
            "firstReadAt": at.addingTimeInterval(60).timeIntervalSince1970
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted])
            .write(to: destination.appending(path: "expected.json"))
    }
}
SWIFT
fi
if [ "$baseline" = "60da7dff8ff3741afc0707652bedea256f9e83df" ]; then
cat > "$source_dir/Sources/V1Fixture/main.swift" <<'SWIFT'
import Foundation
import ReaderCore

// The store of the build before decision 0049 (many notes, and records of the articles in each note). Three notes: an old one with a
// record, the one edited last with two records, and one in between with none.
@main struct V1Fixture {
    @MainActor static func main() throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let at = Date(timeIntervalSince1970: 1_791_152_000)
        let store = try ReaderStore(url: destination.appending(path: "Reader.store"), now: at)
        let xml = """
        <rss version="2.0"><channel><title>合成フィード</title>
        <item><guid>synthetic-1</guid><title>合成記事1</title><link>https://synthetic.example/article/1</link><description>合成RSS要約1</description></item>
        <item><guid>synthetic-2</guid><title>合成記事2</title><link>https://synthetic.example/article/2</link><description>合成RSS要約2</description></item>
        </channel></rss>
        """
        let feed = try store.importFeed(FeedParser.parse(Data(xml.utf8), sourceURL: URL(string: "https://synthetic.example/rss")!), receivedAt: at)
        try store.updateSubscription(feed, title: "合成購読", folder: "技術")
        let articles = store.articles
        try store.markDisplayed(articleID: articles[0].id, at: at.addingTimeInterval(60))
        try store.setStar(articleID: articles[0].id, isStarred: true, at: at)
        let old = try store.createNote(text: "# 古いノート\n", at: at)
        try store.addArticle(articles[0].id, toNote: old.id, at: at.addingTimeInterval(10))
        let last = try store.createNote(text: "# 最後に編集したノート\n本文 🐟", at: at.addingTimeInterval(20))
        try store.addArticle(articles[0].id, toNote: last.id, at: at.addingTimeInterval(30))
        try store.addArticle(articles[1].id, toNote: last.id, at: at.addingTimeInterval(300))
        let middle = try store.createNote(text: "# 真ん中のノート\n", at: at.addingTimeInterval(100))
        let manifest: [String: Any] = [
            "baseline": "60da7dff8ff3741afc0707652bedea256f9e83df", "at": at.timeIntervalSince1970,
            "feedID": feed.id.uuidString, "articleIDs": articles.map(\.id.uuidString),
            "keptNoteID": last.id.uuidString, "keptText": "# 最後に編集したノート\n本文 🐟",
            "keptUpdatedAt": at.addingTimeInterval(300).timeIntervalSince1970,
            "deletedNoteIDs": [old.id.uuidString, middle.id.uuidString],
            "firstReadAt": at.addingTimeInterval(60).timeIntervalSince1970
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted])
            .write(to: destination.appending(path: "expected.json"))
    }
}
SWIFT
fi
if [ "$baseline" = "d37f41b9c72613f207c5fc2d3a59ef2485e23879" ]; then
cat > "$source_dir/Sources/V1Fixture/main.swift" <<'SWIFT'
import Foundation
import ReaderCore

// The store of `main` just before the schema got a version (#449): the six models of 1.0, written without a version. Two
// subscriptions, one in a folder; a read and starred article; 90 days of retention; the note.
@main struct V1Fixture {
    @MainActor static func main() throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let at = Date(timeIntervalSince1970: 1_791_152_000)
        let store = try ReaderStore(url: destination.appending(path: "Reader.store"), now: at)
        let first = """
        <rss version="2.0"><channel><title>合成フィード</title>
        <item><guid>synthetic-1</guid><title>合成記事1</title><link>https://synthetic.example/article/1</link><description>合成RSS要約1</description></item>
        <item><guid>synthetic-2</guid><title>合成記事2</title><link>https://synthetic.example/article/2</link><description>合成RSS要約2</description></item>
        </channel></rss>
        """
        let second = """
        <rss version="2.0"><channel><title>未分類の合成フィード</title>
        <item><guid>other-1</guid><title>合成記事3</title><link>https://other.example/article/1</link><description>合成RSS要約3</description></item>
        </channel></rss>
        """
        let feed = try store.importFeed(FeedParser.parse(Data(first.utf8), sourceURL: URL(string: "https://synthetic.example/rss")!), receivedAt: at)
        try store.updateSubscription(feed, title: "合成購読", folder: "技術")
        let other = try store.importFeed(FeedParser.parse(Data(second.utf8), sourceURL: URL(string: "https://other.example/rss")!), receivedAt: at)
        guard let read = store.articles.first(where: { $0.title == "合成記事1" }) else { fatalError("no synthetic article") }
        try store.markDisplayed(articleID: read.id, at: at.addingTimeInterval(60))
        try store.setStar(articleID: read.id, isStarred: true, at: at.addingTimeInterval(120))
        try store.applyRetention(days: 90, at: at)
        try store.saveNote(text: "# 1.0 の前のノート\n- 残ること", at: at.addingTimeInterval(180))
        let manifest: [String: Any] = [
            "baseline": "d37f41b9c72613f207c5fc2d3a59ef2485e23879", "at": at.timeIntervalSince1970,
            "feedID": feed.id.uuidString, "otherFeedID": other.id.uuidString, "readArticleID": read.id.uuidString,
            "articleIDs": store.articles.map(\.id.uuidString), "noteText": store.note?.text ?? "",
            "firstReadAt": at.addingTimeInterval(60).timeIntervalSince1970, "starredAt": at.addingTimeInterval(120).timeIntervalSince1970
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted])
            .write(to: destination.appending(path: "expected.json"))
    }
}
SWIFT
fi
swift run --package-path "$source_dir" --scratch-path "$source_dir/build" V1Fixture "$destination"
swift --version > "$destination/swift-version.txt"
python3 - "$destination" <<'PY'
from pathlib import Path
import hashlib, sys
p = Path(sys.argv[1])
lines = [f'{hashlib.sha256(f.read_bytes()).hexdigest()}  {f.name}' for f in sorted(p.iterdir()) if f.is_file()]
(p / 'SHA256SUMS').write_text('\n'.join(lines) + '\n')
print(f'Prepared synthetic released-V1 fixture: {p}')
PY
