import SwiftUI
import ReaderCore

struct SubscriptionIconView: View {
    let feed: Feed
    /// The icon's address, given as a value: a refresh writes the feed in a small context, and the refetch that shows it does not notify the
    /// feed (#303). `SubscriptionIconView.url(for:)` makes it.
    let url: URL?
    let loader: ReaderImageLoader
    @State private var loaded: Loaded?
    private struct Loaded { let key: String; let image: NSImage }
    static func url(for feed: Feed) -> URL? { ImageMetadata.favicon(iconURL: feed.iconURL, siteURL: feed.siteURL, sourceURL: feed.sourceURL) }
    private var key: String { feed.id.uuidString + (url?.absoluteString ?? "") }
    var body: some View {
        Group {
            if let loaded, loaded.key == key { Image(nsImage: loaded.image).resizable().scaledToFit() }
            else { Image(systemName: feed.symbol).foregroundStyle(.secondary) }
        }.frame(width: 18, height: 18).accessibilityHidden(true)
        .task(id: key) {
            loaded = nil
            guard let url else { return }
            let requestedKey = key
            do {
                guard let data = try await loader.image(url: url, at: .now) else { return }
                try Task.checkCancellation()
                if let image = NSImage(data: data) { loaded = Loaded(key: requestedKey, image: image) }
            } catch { /* Keep the subscription readable with its fallback icon. */ }
        }
    }
}
