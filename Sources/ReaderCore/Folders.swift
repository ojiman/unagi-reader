import Foundation

extension ReaderStore {
    public func folderArticleIDs(folder: String, keeping: UUID?) -> [UUID] {
        _ = contentRevision
        let values = folderIndex[folder] ?? []
        guard let keeping, !values.contains(keeping), article(id: keeping) != nil else { return values }
        let members = Set(values)
        return articleIDs.filter { members.contains($0) || $0 == keeping }
    }
    public func folderUnreadCount(folder: String) -> Int { folderUnreadCounts[folder] ?? 0 }
    public func moveFeed(id: UUID, toFolder: String) throws {
        try reloadIfNeeded()
        guard let feed = feed(id: id) else { return }
        let name = SingleLineText.name(toFolder)
        guard feed.folder != name else { return }
        feed.folder = name; try save(); try reload()
    }
    /// Moves subscriptions into a folder (empty means unfiled), with one save. Returns whether any of them changed folder: dropping on the
    /// folder a subscription is already in, or an unknown subscription, changes nothing and saves nothing.
    @discardableResult public func moveFeeds(ids: [UUID], toFolder: String) throws -> Bool {
        try reloadIfNeeded()
        let name = SingleLineText.name(toFolder)
        let moving = ids.compactMap { feed(id: $0) }.filter { $0.folder != name }
        guard !moving.isEmpty else { return false }
        for feed in moving { feed.folder = name }
        try save(); try reload()
        return true
    }
    public func renameFolder(from: String, to: String) throws {
        try reloadIfNeeded()
        let source = SingleLineText.name(from), target = SingleLineText.name(to)
        guard source != target else { return }
        for feed in feeds where feed.folder == source { feed.folder = target }
        try save(); try reload()
    }
}
