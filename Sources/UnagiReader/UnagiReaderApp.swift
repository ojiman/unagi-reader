import SwiftUI
import ReaderCore

@main
struct UnagiReaderApp: App {
    @State private var store: ReaderStore?
    @State private var refresh: FeedRefreshController?
    @State private var imageLoader: ReaderImageLoader?
    @State private var startupError: String?
    @State private var lifecycleError: String?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "system"

    init() {
        do {
            let args = ProcessInfo.processInfo.arguments
            let directory: URL
            if let index = args.firstIndex(of: "--data-directory"), args.indices.contains(index + 1) {
                directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
            } else {
                directory = URL.applicationSupportDirectory.appending(path: AppIdentity.dataFolderName, directoryHint: .isDirectory)
            }
            if ReadingBenchmark.requested { try ReadingBenchmark.validateFixture(at: directory, explicit: args.contains("--data-directory")) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = try ReaderStore(url: directory.appending(path: "Reader.store"), seedDemo: args.contains("--seed-demo"))
            _store = State(initialValue: store)
            let client = ReadingBenchmark.requested ? FeedClient(http: ReadingBenchmark.SyntheticHTTP()) : FeedClient()
            _refresh = State(initialValue: FeedRefreshController(store: store, client: client))
            // The copies of the note that the hand-off to Claude made are not deleted by anything now (decision 0049).
            do { try LegacyHandoffFolder.remove(in: directory) } catch { _lifecycleError = State(initialValue: error.localizedDescription) }
            let cache = args.contains("--data-directory") ? directory.appending(path: "Cache/Images") : URL.cachesDirectory.appending(path: "\(AppIdentity.dataFolderName)/Images")
            _imageLoader = State(initialValue: ReaderImageLoader(directory: cache))
        } catch {
            _startupError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        Window("Unagi Reader", id: "reader") {
            Group {
                if let store, let refresh, let imageLoader { ReaderView(store: store, refresh: refresh, imageLoader: imageLoader) }
                else {
                    ContentUnavailableView(String(localized: "Could Not Open Library", bundle: ReaderLocalization.bundle), systemImage: "externaldrive.badge.exclamationmark",
                        description: Text(startupError ?? String(localized: "An unknown error occurred.", bundle: ReaderLocalization.bundle)))
                        .frame(width: 600, height: 400)
                }
            }
            .preferredColorScheme(ReaderTheme(stored: appearance).colorScheme)
            .onChange(of: appearance) { _, new in ThemeState.shared.sepia = ReaderTheme(stored: new) == .sepia }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { purgeContent(); Task { await refresh?.refresh() } }
            }
            .task {
                await refresh?.refresh()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1800)) } catch { break }
                    purgeContent()
                    await refresh?.refresh()
                }
            }
            .task {
                guard ReaderPerformance.output != nil else { return }
                while !Task.isCancelled {
                    ReaderPerformance.heartbeat()
                    do { try await Task.sleep(for: .milliseconds(20)) } catch { break }
                }
                ReaderPerformance.write()
            }
            .alert(String(localized: "Could Not Clean Up Saved Data", bundle: ReaderLocalization.bundle), isPresented: Binding(get: { lifecycleError != nil }, set: { if !$0 { lifecycleError = nil } })) {
                Button(String(localized: "Try Again", bundle: ReaderLocalization.bundle)) { lifecycleError = nil; purgeContent() }
                Button(String(localized: "Close", bundle: ReaderLocalization.bundle)) { lifecycleError = nil }
            } message: { Text(lifecycleError ?? "") }

        }
        .defaultSize(width: 1240, height: 810)
        // No title bar and no system toolbar: each column draws its own band (decision 0057).
        .windowStyle(.hiddenTitleBar)
        .commands { CommandGroup(replacing: .newItem) {}; OPMLCommands(); ReaderMenuCommands(); TranslationCommands(); ShortcutHelpCommands() }
        Settings {
            if let store { ReaderSettingsView(store: store, appearance: $appearance) }
        }
    }
    private func purgeContent() {
        do { try store?.purgeExpired(at: .now) } catch { lifecycleError = error.localizedDescription }
    }
}
