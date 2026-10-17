import SwiftUI
import UniformTypeIdentifiers
import ReaderCore

/// The File menu's 「OPMLを取り込む…」 and 「OPMLを書き出す…」. The window that shows the library publishes the actions; with no such
/// window the items are off. They have no key shortcut: they are rare actions.
struct OPMLCommands: Commands {
    @FocusedValue(\.importOPML) private var importOPML
    @FocusedValue(\.exportOPML) private var exportOPML

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button(String(localized: "Import OPML…", bundle: ReaderLocalization.bundle)) { importOPML?() }.disabled(importOPML == nil)
            Button(String(localized: "Export OPML…", bundle: ReaderLocalization.bundle)) { exportOPML?() }.disabled(exportOPML == nil)
        }
    }
}

private struct ImportOPMLKey: FocusedValueKey { typealias Value = () -> Void }
private struct ExportOPMLKey: FocusedValueKey { typealias Value = () -> Void }

extension FocusedValues {
    var importOPML: (() -> Void)? {
        get { self[ImportOPMLKey.self] }
        set { self[ImportOPMLKey.self] = newValue }
    }
    var exportOPML: (() -> Void)? {
        get { self[ExportOPMLKey.self] }
        set { self[ExportOPMLKey.self] = newValue }
    }
}

enum OPMLFilePanel {
    /// Asks for one OPML file (nil when the person cancels).
    @MainActor static func chooseFile() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "opml"), .xml].compactMap { $0 }
        panel.message = String(localized: "Choose an OPML file to import.", bundle: ReaderLocalization.bundle)
        panel.prompt = String(localized: "Import", bundle: ReaderLocalization.bundle)
        guard let window = NSApp.keyWindow else { return panel.runModal() == .OK ? panel.url : nil }
        return await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { response in continuation.resume(returning: response == .OK ? panel.url : nil) }
        }
    }

    /// Asks where to save the exported subscriptions (nil when the person cancels).
    @MainActor static func chooseDestination(suggestedName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "opml") ?? .xml]
        panel.nameFieldStringValue = suggestedName
        panel.message = String(localized: "Save your subscriptions as an OPML file.", bundle: ReaderLocalization.bundle)
        panel.prompt = String(localized: "Export", bundle: ReaderLocalization.bundle)
        guard let window = NSApp.keyWindow else { return panel.runModal() == .OK ? panel.url : nil }
        return await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { response in continuation.resume(returning: response == .OK ? panel.url : nil) }
        }
    }
}

/// What the library window adds for OPML: the actions the File menu runs, the alert with the import's report, and the alert when an
/// export could not be written. It is a modifier of its own because the window's body is already long, and the CI compiler gives up on
/// a longer chain.
struct OPMLImportPresentation: ViewModifier {
    let flow: OPMLImportFlow
    @State private var export: OPMLExportFlow

    init(flow: OPMLImportFlow, store: ReaderStore) {
        self.flow = flow
        _export = State(initialValue: OPMLExportFlow(store: store, chooseDestination: { await OPMLFilePanel.chooseDestination(suggestedName: $0) }))
    }

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.importOPML, { Task { await flow.start() } })
            .focusedSceneValue(\.exportOPML, { Task { await export.start() } })
            .alert(String(localized: "The subscriptions could not be exported", bundle: ReaderLocalization.bundle),
                   isPresented: Binding(get: { export.failure != nil }, set: { if !$0 { export.dismissFailure() } })) {
                Button(String(localized: "OK", bundle: ReaderLocalization.bundle)) { export.dismissFailure() }
            } message: {
                if let failure = export.failure { Text(failure) }
            }
            .alert(flow.report?.title ?? "", isPresented: Binding(get: { flow.report != nil }, set: { if !$0 { flow.dismissReport() } })) {
                Button(String(localized: "OK", bundle: ReaderLocalization.bundle)) { flow.dismissReport() }
            } message: {
                if let message = flow.report?.message, !message.isEmpty { Text(message) }
            }
    }
}
