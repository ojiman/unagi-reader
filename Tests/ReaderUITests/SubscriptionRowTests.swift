import Foundation
import ReaderCore
import Testing
@testable import UnagiReader

/// A sidebar row is rebuilt only when what it shows changes (#249): every shown value takes part in the comparison, the actions do not.
@MainActor struct SubscriptionRowTests {
    private let feed = Feed(title: "合成購読", symbol: "dot.radiowaves.left.and.right")
    private let loader = ReaderImageLoader(directory: FileManager.default.temporaryDirectory.appending(path: "row-icons-" + UUID().uuidString))

    private func row(title: String = "合成購読", folder: String = "", folders: [String] = ["技術"], unread: Int = 3, error: String? = nil,
                     editing: String? = nil, moving: Bool = false, iconURL: URL? = nil, reduceMotion: Bool = false, onRename: @escaping () -> Void = {}) -> SubscriptionRow {
        SubscriptionRow(feed: feed, feedID: feed.id, title: title, folder: folder, folders: folders, unread: unread, error: error, editing: editing,
            moving: moving, iconURL: iconURL, reduceMotion: reduceMotion, imageLoader: loader,
            actions: SubscriptionRow.Actions(finishEdit: { _ in }, refresh: {}, rename: onRename, beginMove: {}, endMove: {}, move: { _ in }, unsubscribe: {}))
    }

    @Test func theSameValuesWithOtherActionsAreEqual() {
        #expect(row() == row(onRename: { print("another action") }))
    }

    @Test func eachShownValueMakesTheRowDifferent() {
        let base = row()
        #expect(base != row(title: "別の名前"))
        #expect(base != row(folder: "技術"))
        #expect(base != row(folders: ["技術", "読み物"]))
        #expect(base != row(unread: 4))                        // a read mark changes the count
        #expect(base != row(error: "合成エラー"))
        #expect(base != row(editing: "合成購読"))
        #expect(base != row(moving: true))
        #expect(base != row(iconURL: URL(string: "https://feed.example/icon.png")))   // a refresh can change it without notifying the feed
        #expect(base != row(reduceMotion: true))              // the move action reads it
    }

    @Test func anotherSubscriptionIsDifferent() {
        let other = Feed(title: "合成購読", symbol: "dot.radiowaves.left.and.right")
        let a = row()
        let b = SubscriptionRow(feed: other, feedID: other.id, title: a.title, folder: a.folder, folders: a.folders, unread: a.unread, error: a.error,
            editing: a.editing, moving: a.moving, reduceMotion: a.reduceMotion, imageLoader: loader, actions: a.actions)
        #expect(a != b)
    }

    /// Issue #333: after save recovery the store has a new model for the same subscription. The row must take it, so its icon observes
    /// the model that later changes, not the old one.
    @Test func aNewModelOfTheSameSubscriptionIsDifferent() {
        let replacement = Feed(title: "合成購読", symbol: "dot.radiowaves.left.and.right")
        replacement.id = feed.id
        let a = row()
        let b = SubscriptionRow(feed: replacement, feedID: replacement.id, title: a.title, folder: a.folder, folders: a.folders, unread: a.unread,
            error: a.error, editing: a.editing, moving: a.moving, reduceMotion: a.reduceMotion, imageLoader: loader, actions: a.actions)
        #expect(a != b)
    }
}
