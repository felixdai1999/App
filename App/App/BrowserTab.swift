import SwiftUI
import WebKit
import Combine

@Observable
class BrowserTab: NSObject, Identifiable {
    let id = UUID()
    var title: String = "New Tab"
    var currentURL: URL?
    var isLoading: Bool = false
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var estimatedProgress: Double = 0
    var zoomLevel: CGFloat = 1.0
    var isDesktopMode: Bool = false
    var toolbarVisible: Bool = true

    #if os(iOS) || os(visionOS)
    var snapshotImage: UIImage?
    #elseif os(macOS)
    var snapshotImage: NSImage?
    #endif

    var snapshotSwiftUIImage: Image? {
        #if os(iOS) || os(visionOS)
        guard let img = snapshotImage else { return nil }
        return Image(uiImage: img)
        #elseif os(macOS)
        guard let img = snapshotImage else { return nil }
        return Image(nsImage: img)
        #endif
    }

    let webView: WKWebView
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var lastFindText = ""
    @ObservationIgnored private var findDebounceTask: Task<Void, Never>?
    @ObservationIgnored var onPageLoaded: ((String, URL) -> Void)?
    @ObservationIgnored var onOpenInNewTab: ((URL) -> Void)?
    @ObservationIgnored var onURLChanged: (() -> Void)?

    let isPrivate: Bool

    init(url: URL? = nil, isPrivate: Bool = false) {
        self.isPrivate = isPrivate
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        if isPrivate {
            configuration.websiteDataStore = .nonPersistent()
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true

        super.init()

        webView.uiDelegate = self
        setupObservers()

        if let url {
            load(url)
        }
    }

    private func setupObservers() {
        webView.publisher(for: \.title)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.title = (value?.isEmpty == false) ? value! : "New Tab"
            }
            .store(in: &cancellables)

        webView.publisher(for: \.url)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.currentURL = value
                if value != nil {
                    self?.onURLChanged?()
                }
            }
            .store(in: &cancellables)

        webView.publisher(for: \.isLoading)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                let wasLoading = self?.isLoading ?? false
                self?.isLoading = value
                if wasLoading && !value,
                   let url = self?.currentURL,
                   let title = self?.title,
                   title != "New Tab" {
                    self?.onPageLoaded?(title, url)
                }
            }
            .store(in: &cancellables)

        webView.publisher(for: \.canGoBack)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canGoBack = value
            }
            .store(in: &cancellables)

        webView.publisher(for: \.canGoForward)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canGoForward = value
            }
            .store(in: &cancellables)

        webView.publisher(for: \.estimatedProgress)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.estimatedProgress = value
            }
            .store(in: &cancellables)
    }

    // MARK: - Navigation

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func loadRequest(_ input: String) {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if looksLikeURL(text) {
            if !text.hasPrefix("http://") && !text.hasPrefix("https://") {
                text = "https://" + text
            }
            if let url = URL(string: text) {
                load(url)
                return
            }
        }

        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
            load(url)
        }
    }

    private func looksLikeURL(_ text: String) -> Bool {
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return true }
        if text.contains(" ") { return false }
        return text.contains(".") && !text.hasSuffix(".")
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stopLoading() { webView.stopLoading() }

    func takeSnapshot() {
        guard currentURL != nil else { return }
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            self?.snapshotImage = image
        }
    }

    // MARK: - Zoom

    func zoomIn() {
        zoomLevel = min(zoomLevel + 0.1, 3.0)
        webView.pageZoom = zoomLevel
    }

    func zoomOut() {
        zoomLevel = max(zoomLevel - 0.1, 0.3)
        webView.pageZoom = zoomLevel
    }

    func resetZoom() {
        zoomLevel = 1.0
        webView.pageZoom = 1.0
    }

    // MARK: - Desktop Mode

    func toggleDesktopMode() {
        isDesktopMode.toggle()
        if isDesktopMode {
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        } else {
            webView.customUserAgent = nil
        }
        reload()
    }

    // MARK: - Find in Page (debounced)

    func findInPage(_ text: String) {
        findDebounceTask?.cancel()
        guard !text.isEmpty else {
            clearFind()
            return
        }
        lastFindText = text
        let escaped = text.jsEscaped
        findDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            try? await self?.webView.evaluateJavaScript("window.find('\(escaped)', false, false, true)")
        }
    }

    func findInPageNext() {
        guard !lastFindText.isEmpty else { return }
        let escaped = lastFindText.jsEscaped
        webView.evaluateJavaScript("window.find('\(escaped)', false, false, true)")
    }

    func findInPagePrevious() {
        guard !lastFindText.isEmpty else { return }
        let escaped = lastFindText.jsEscaped
        webView.evaluateJavaScript("window.find('\(escaped)', false, true, true)")
    }

    func clearFind() {
        findDebounceTask?.cancel()
        lastFindText = ""
        webView.evaluateJavaScript("window.getSelection().removeAllRanges()")
    }
}

// MARK: - WKUIDelegate

extension BrowserTab: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url, let onOpenInNewTab {
                onOpenInNewTab(url)
            } else {
                webView.load(navigationAction.request)
            }
        }
        return nil
    }
}

// MARK: - Helpers

private extension String {
    var jsEscaped: String {
        self.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
