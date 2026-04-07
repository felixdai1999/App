import SwiftUI
import WebKit
import Combine

#if os(iOS) || os(visionOS)
struct WebView: UIViewRepresentable {
    let tab: BrowserTab
    let bottomBarHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab)
    }

    func makeUIView(context: Context) -> WKWebView {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleRefresh),
            for: .valueChanged
        )
        tab.webView.scrollView.refreshControl = refreshControl
        tab.webView.scrollView.delegate = context.coordinator
        tab.webView.scrollView.contentInsetAdjustmentBehavior = .never

        // Add bottom inset so content isn't hidden behind safe area
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first
        let bottomInset = (window?.safeAreaInsets.bottom ?? 0) + bottomBarHeight
        let topInset = window?.safeAreaInsets.top ?? 0
        
        tab.webView.scrollView.contentInset.bottom = bottomInset
        tab.webView.scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
        tab.webView.scrollView.contentInset.top = topInset
        tab.webView.scrollView.verticalScrollIndicatorInsets.top = topInset

        return tab.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first
        let bottomInset = (window?.safeAreaInsets.bottom ?? 0) + bottomBarHeight
        webView.scrollView.contentInset.bottom = bottomInset
        webView.scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        let tab: BrowserTab
        private var cancellable: AnyCancellable?
        private var lastScrollY: CGFloat = 0
        private var scrollAccumulator: CGFloat = 0

        init(tab: BrowserTab) {
            self.tab = tab
            super.init()
            cancellable = tab.webView.publisher(for: \.isLoading)
                .receive(on: RunLoop.main)
                .sink { [weak self] isLoading in
                    if !isLoading {
                        self?.tab.webView.scrollView.refreshControl?.endRefreshing()
                    }
                }
        }

        @objc func handleRefresh() {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            tab.reload()
        }

        // MARK: - UIScrollViewDelegate

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let y = scrollView.contentOffset.y
            let topInset = scrollView.contentInset.top
            let realY = y + topInset
            let delta = y - lastScrollY

            // Always show toolbar at the top (including bouncing up)
            if realY <= 0 {
                if !tab.toolbarVisible {
                    tab.toolbarVisible = true
                }
                scrollAccumulator = 0
                lastScrollY = y
                return
            }

            // Ignore programmatic layout shifts (like reloading)
            let isUserScrolling = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
            if !isUserScrolling || abs(delta) > 150 {
                lastScrollY = y
                return
            }

            if delta > 0 {
                // Scrolling down
                scrollAccumulator += delta
                if scrollAccumulator > 40 && tab.toolbarVisible {
                    tab.toolbarVisible = false
                }
            } else if delta < 0 {
                // Scrolling up
                scrollAccumulator += delta
                if scrollAccumulator < -25 && !tab.toolbarVisible {
                    tab.toolbarVisible = true
                }
            }

            scrollAccumulator = max(-80, min(80, scrollAccumulator))
            lastScrollY = y
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            lastScrollY = scrollView.contentOffset.y
            scrollAccumulator = 0
        }
    }
}
#elseif os(macOS)
struct WebView: NSViewRepresentable {
    let tab: BrowserTab

    func makeNSView(context: Context) -> WKWebView {
        tab.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
#endif
