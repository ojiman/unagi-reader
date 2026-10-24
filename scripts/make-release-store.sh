#!/bin/bash
# Makes a synthetic library with the source of a release tag (specification 7.1, #450): from 1.0, every later version must open it and
# keep everything. Writes Reader.store* and expected.json (what that release itself read back) to a new directory.
#
#   make-release-store.sh NEW_DIRECTORY [TAG]      TAG defaults to v1.0.0; NEW_DIRECTORY is /private/tmp/unagi-reader-*
#
# Synthetic data only. The tag must be in this clone (`git fetch origin tag v1.0.0` in a shallow one).
set -euo pipefail
cd "$(dirname "$0")/.."
if [ $# -lt 1 ] || [ $# -gt 2 ]; then echo "Usage: make-release-store.sh NEW_DIRECTORY [TAG]" >&2; exit 2; fi
destination=$1 tag=${2:-v1.0.0}
case "$tag" in v[0-9]*.[0-9]*.[0-9]*) ;; *) echo "make-release-store.sh: '$tag' is not a release tag vX.Y.Z" >&2; exit 2 ;; esac
python3 - "$destination" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
if p.resolve().parent != Path('/private/tmp') or not p.name.startswith('unagi-reader-'):
    sys.exit('make-release-store.sh: use a new /private/tmp/unagi-reader-* directory')
if p.exists():
    sys.exit('make-release-store.sh: the directory already exists; use a new one')
PY
commit=$(git rev-parse --verify --quiet "refs/tags/$tag^{commit}") || { echo "make-release-store.sh: no tag '$tag' in this clone" >&2; exit 1; }
source_dir=$(mktemp -d /private/tmp/unagi-reader-release-source.XXXXXX)
trap 'rm -rf "$source_dir"' EXIT
git archive "$commit" | tar -x -C "$source_dir"
# A small executable beside the app, built with the release's own ReaderCore.
python3 - "$source_dir/Package.swift" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
app = '.executableTarget(name: "UnagiReader",'
if s.count(app) != 1:
    sys.exit('make-release-store.sh: the release Package.swift has no single UnagiReader target')
p.write_text(s.replace(app, '.executableTarget(name: "ReleaseStore", dependencies: ["ReaderCore"]),\n        ' + app))
PY
mkdir -p "$source_dir/Sources/ReleaseStore"
cat > "$source_dir/Sources/ReleaseStore/main.swift" <<'SWIFT'
import Foundation
import ReaderCore

// Two subscriptions (one in a folder), an article with a body, one with a summary only, one whose body was deleted, a read and starred
// article, a second Star, 90 days of retention and the note. expected.json records what this release reads back.
@main struct ReleaseStore {
    @MainActor static func main() throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let tag = CommandLine.arguments[2], commit = CommandLine.arguments[3]
        let at = Date(timeIntervalSince1970: 1_792_800_000)
        let store = try ReaderStore(url: destination.appending(path: "Reader.store"), now: at)
        let filed = """
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel><title>合成フィード</title>
        <item><guid>body</guid><title>本文のある記事</title><link>https://synthetic.example/article/body</link><description>本文の要約</description>
        <content:encoded><![CDATA[<p>合成の本文です。</p><p><a href="https://synthetic.example/linked">リンク</a>のある段落。</p>]]></content:encoded></item>
        <item><guid>summary</guid><title>要約だけの記事</title><link>https://synthetic.example/article/summary</link><description>要約だけの本文</description></item>
        <item><guid>deleted</guid><title>本文を消した記事</title><link>https://synthetic.example/article/deleted</link><description>消える要約</description>
        <content:encoded><![CDATA[<p>消える本文</p>]]></content:encoded></item>
        </channel></rss>
        """
        let unfiled = """
        <rss version="2.0"><channel><title>未分類の合成フィード</title>
        <item><guid>other</guid><title>未分類の記事</title><link>https://other.example/article/1</link><description>未分類の要約</description></item>
        </channel></rss>
        """
        let feed = try store.importFeed(FeedParser.parse(Data(filed.utf8), sourceURL: URL(string: "https://synthetic.example/rss")!), receivedAt: at)
        try store.updateSubscription(feed, title: "合成購読", folder: "技術")
        let other = try store.importFeed(FeedParser.parse(Data(unfiled.utf8), sourceURL: URL(string: "https://other.example/rss")!), receivedAt: at)
        func article(_ title: String) -> Article {
            guard let found = store.articles.first(where: { $0.title == title }) else { fatalError("no synthetic article \(title)") }
            return found
        }
        let read = article("本文のある記事"), deleted = article("本文を消した記事"), starred = article("未分類の記事")
        try store.markDisplayed(articleID: read.id, at: at.addingTimeInterval(60))
        try store.setStar(articleID: read.id, isStarred: true, at: at.addingTimeInterval(120))
        try store.setStar(articleID: starred.id, isStarred: true, at: at.addingTimeInterval(130))
        try store.deleteContent(articleIDs: [deleted.id], at: at.addingTimeInterval(140))
        try store.applyRetention(days: 90, at: at.addingTimeInterval(150))
        try store.saveNote(text: "# 1.0 のノート\n- 自分の言葉で", at: at.addingTimeInterval(180))
        var articles: [[String: Any]] = []
        for item in store.articles {
            let content = try store.content(articleID: item.id, at: at.addingTimeInterval(200))
            articles.append([
                "id": item.id.uuidString, "feedID": item.feedID.uuidString, "title": item.title, "identityKey": item.identityKey ?? "",
                "firstReadAt": item.firstReadAt?.timeIntervalSince1970 ?? -1, "starredAt": item.starredAt?.timeIntervalSince1970 ?? -1,
                "text": content.map { $0.text as Any } ?? NSNull(), "links": content?.bodyParagraphs.flatMap { $0.links.map(\.url) } ?? []
            ])
        }
        let manifest: [String: Any] = [
            "tag": tag, "commit": commit, "at": at.timeIntervalSince1970, "readAt": at.addingTimeInterval(200).timeIntervalSince1970,
            "feeds": store.feeds.map { ["id": $0.id.uuidString, "title": $0.title, "folder": $0.folder, "sourceURL": $0.sourceURL] },
            "feedID": feed.id.uuidString, "otherFeedID": other.id.uuidString, "articles": articles,
            "retentionDays": store.retentionDays, "noteText": store.note?.text ?? "", "noteCount": store.notes.count
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted])
            .write(to: destination.appending(path: "expected.json"))
    }
}
SWIFT
mkdir "$destination"
swift run --package-path "$source_dir" --scratch-path "$source_dir/build" ReleaseStore "$destination" "$tag" "$commit"
printf 'Made the %s store (%s): %s\n' "$tag" "$commit" "$destination"
