import SwiftUI
import WebKit
import ReaderCore

/// When the original page's web view is shown (issue #218). A page that has not started to arrive is blank, and while the column was
/// still widening it kept the width of an intermediate frame: a white page with a dark, unexplained column beside it. So the web
/// view stays hidden behind the app's surface, with the loading spinner in the middle, until the page has painted its first content
/// (or has finished loading without any).
struct OriginalPageReveal {
    private var didPaint = false
    private var didFail = false
    var showsPage: Bool { didPaint && !didFail }
    var showsPlaceholder: Bool { !didPaint && !didFail }
    mutating func painted() { didPaint = true }
    mutating func failed() { didFail = true }
}

struct OriginalPageView: View {
    let url: URL
    let onClose: () -> Void
    let onCommand: (ReaderCommand) -> Void
    @State private var failure: String?
    @State private var reveal = OriginalPageReveal()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            if let failure {
                OriginalFailureView(message: failure, onCommand: onCommand)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                OriginalWebView(url: url, onClose: onClose, onCommand: onCommand,
                                onFailure: { reveal.failed(); failure = $0 }, onPainted: { reveal.painted() })
                    .opacity(reveal.showsPage ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: reveal.showsPage)
                if reveal.showsPlaceholder {
                    // The ✕ and the host name are in the article band (decision 0057); the column says that it is loading.
                    ProgressView().controlSize(.regular)
                        .accessibilityLabel(String(localized: "Loading Original Page", bundle: ReaderLocalization.bundle))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.surfaceColor)
    }
}

// This input target exists only after the page has failed and its editable
// web content has been removed. It never handles keys from a live page input.
@MainActor final class OriginalFailureHostingView<Content: View>: NSHostingView<Content> {
    var onCommand: (ReaderCommand) -> Void = { _ in }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        let responder = window.firstResponder
        // A late failure must not take the keyboard after the person moved to the note or list.
        guard responder == nil || responder === window || ReaderKeyboardCommands.isInOriginalPage(responder) else { return }
        window.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) {
        guard window?.firstResponder === self, window?.attachedSheet == nil,
              let command = ReaderKeyboardCommands.command(for: event) else { super.keyDown(with: event); return }
        onCommand(command)
    }
}

private struct OriginalFailureView: NSViewRepresentable {
    let message: String
    let onCommand: (ReaderCommand) -> Void
    private var content: AnyView {
        AnyView(ContentUnavailableView(String(localized: "Could Not Open Original Page", bundle: ReaderLocalization.bundle), systemImage: "wifi.exclamationmark", description: Text(message)))
    }
    func makeNSView(context: Context) -> OriginalFailureHostingView<AnyView> {
        let view = OriginalFailureHostingView(rootView: content)
        view.sizingOptions = []
        view.onCommand = onCommand
        return view
    }
    func updateNSView(_ view: OriginalFailureHostingView<AnyView>, context: Context) {
        view.rootView = content; view.onCommand = onCommand
    }
}

@MainActor final class OriginalReaderWebView: WKWebView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Set this window's input target without activating another application.
        // Later clicks in page inputs retain their own focus.
        if let window { window.makeFirstResponder(self) }
    }
}

private struct OriginalWebView: NSViewRepresentable {
    let url: URL
    let onClose: () -> Void
    let onCommand: (ReaderCommand) -> Void
    let onFailure: (String) -> Void
    let onPainted: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFailure: onFailure, onPainted: onPainted) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Original-page browsing has a separate, temporary session.
        configuration.websiteDataStore = .nonPersistent()
        let view = OriginalReaderWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        context.coordinator.keyboard = OriginalKeyboardBridge(onCommand: onCommand)
        context.coordinator.keyboard?.install(in: view)
        let paint = OriginalPaintBridge(onPainted: { [weak coordinator = context.coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.painted(view)
        })
        paint.install(in: view)
        context.coordinator.paint = paint
        view.load(URLRequest(url: url))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.active = false
        view.stopLoading(); view.navigationDelegate = nil; view.uiDelegate = nil
        coordinator.keyboard?.uninstall(); coordinator.keyboard = nil
        coordinator.paint?.uninstall(from: view); coordinator.paint = nil
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onFailure: (String) -> Void
        let onPainted: () -> Void
        var active = true
        var keyboard: OriginalKeyboardBridge?
        var paint: OriginalPaintBridge?
        init(onFailure: @escaping (String) -> Void, onPainted: @escaping () -> Void) {
            self.onFailure = onFailure; self.onPainted = onPainted
        }
        /// The page has painted: it is laid out for the column's width now, and the web view is shown.
        func painted(_ webView: WKWebView) {
            guard active else { return }
            webView.needsLayout = true; webView.layoutSubtreeIfNeeded()
            onPainted()
        }
        /// A page that finishes without painting anything (a blank page) is shown as it is.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { painted(webView) }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, ArticleURL.validated(url.absoluteString) != nil else { decisionHandler(.cancel); return }
            if action.targetFrame == nil { webView.load(action.request); decisionHandler(.cancel) }
            else { decisionHandler(.allow) }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error) }
        private func report(_ error: Error) {
            if active && (error as NSError).code != NSURLErrorCancelled { onFailure(error.localizedDescription) }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    }
}
