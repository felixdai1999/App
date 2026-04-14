import SwiftUI
#if os(iOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Button Styles

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Content View

enum CollectionTab: String, CaseIterable, Identifiable {
    case bookmarks = "Bookmarks"
    case favorites = "Favorites"
    case history = "History"
    var id: String { rawValue }
}

struct ContentView: View {
    private enum SwipePreviewDirection: Equatable {
        case previous
        case next
    }

    @State private var viewModel = BrowserViewModel()
    @State private var addressText = ""
    @State private var addressBarOffset: CGFloat = 0
    @State private var addressBarVerticalOffset: CGFloat = 0
    @State private var addressBarWidth: CGFloat = 0
    @FocusState private var isAddressBarFocused: Bool
    @State private var showTabOverview = false
    @State private var showFindBar = false
    @State private var findText = ""
    @FocusState private var isFindBarFocused: Bool
    @State private var showHistory = false
    @State private var showBookmarks = false
    @State private var selectedCollectionTab: CollectionTab = .bookmarks
    @State private var collectionSearchText = ""
    @State private var showSettings = false
    @State private var historySearchText = ""
    @State private var bookmarkSearchText = ""
    @State private var bookmarkSortIsRecentFirst = true
    @State private var showCustomizeStartPage = false
    @State private var showStartPageOverlay = false
    @State private var bottomContainerWidth: CGFloat = 300
    @State private var showClearHistoryConfirmation = false
    @State private var showCloseAllTabsConfirmation = false
    @State private var googleAutocompleteQueries: [String] = []
    @State private var googleSuggestTask: Task<Void, Never>?
    @State private var focusedAddressSeedText = ""
    @State private var hasEditedAddressTextSinceFocus = false
    @State private var recentSearchQueries: [String] = []
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false
    @State private var onboardingStep = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private let recentSearchesDefaultsKey = "recent_search_queries"

    private var shouldShowTabStrip: Bool {
        guard viewModel.tabs.count > 1 else { return false }
        #if os(iOS)
        let isEligibleClass = horizontalSizeClass == .regular || verticalSizeClass == .compact
        return isEligibleClass && isToolbarExpanded && viewModel.showTabStrip
        #else
        return viewModel.showTabStrip
        #endif
    }

    private var isToolbarExpanded: Bool {
        #if os(iOS)
        return viewModel.selectedTab?.toolbarVisible ?? true
        #else
        return true
        #endif
    }

    var body: some View {
        ZStack {
            browserView
                .opacity(showTabOverview ? 0 : 1)
                .allowsHitTesting(!showTabOverview)

            if showStartPageOverlay && addressBarOnTop {
                floatingStartPageOverlay
            }

            if showTabOverview {
                tabOverview
                    .transition(.opacity)
            }

            if shouldShowAutocompleteOverlay {
                autocompleteFloatingLayer
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(200)
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.12), value: showTabOverview)
        .onChange(of: viewModel.selectedTabID) {
            syncAddressText()
            if showFindBar { dismissFindBar() }
        }
        .onChange(of: viewModel.selectedTab?.currentURL) {
            if !isAddressBarFocused {
                syncAddressText()
            }
        }
        .onChange(of: isAddressBarFocused) { _, focused in
            if focused {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                addressText = viewModel.selectedTab?.currentURL?.absoluteString ?? ""
                focusedAddressSeedText = addressText
                hasEditedAddressTextSinceFocus = false
                if viewModel.selectedTab?.currentURL != nil {
                    withAnimation(.spring(duration: 0.4, bounce: 0.08)) {
                        showStartPageOverlay = true
                    }
                }
            } else {
                googleSuggestTask?.cancel()
                googleAutocompleteQueries = []
                hasEditedAddressTextSinceFocus = false
                withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
                    showStartPageOverlay = false
                }
                syncAddressText()
            }
        }
        .onChange(of: addressText) { _, text in
            if isAddressBarFocused && !hasEditedAddressTextSinceFocus && text != focusedAddressSeedText {
                hasEditedAddressTextSinceFocus = true
            }
            fetchGoogleAutocompleteSuggestions(for: text)
        }
        .onAppear {
            loadRecentSearches()
            if !hasSeenOnboarding {
                showOnboarding = true
            }
            #if os(iOS)
            if let pendingAction = AppDelegate.pendingQuickAction {
                handleHomeScreenQuickAction(pendingAction)
                AppDelegate.pendingQuickAction = nil
            }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeScreenQuickActionTriggered)) { notification in
            #if os(iOS)
            guard let action = notification.object as? HomeScreenQuickAction else { return }
            handleHomeScreenQuickAction(action)
            #endif
        }
        .overlay { keyboardShortcuts }
        .sensoryFeedback(.selection, trigger: viewModel.selectedTabID)
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.tabs.count)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.7), trigger: viewModel.bookmarkStore.bookmarks.count)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: showFindBar)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.6), trigger: showTabOverview)
        .sheet(isPresented: $showHistory) {
            selectedCollectionTab = .history
            return collectionSheet
        }
        .sheet(isPresented: $showBookmarks) {
            collectionSheet
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            onboardingScreen
        }
        .preferredColorScheme(viewModel.theme.colorScheme)
    }

    // MARK: - Keyboard Shortcuts

    @ViewBuilder
    private var keyboardShortcuts: some View {
        Group {
            Button("") {
                withAnimation(.snappy(duration: 0.25)) {
                    viewModel.addNewTab()
                }
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("") {
                if let id = viewModel.selectedTabID {
                    withAnimation(.snappy(duration: 0.25)) {
                        viewModel.closeTab(id)
                    }
                }
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("") {
                isAddressBarFocused = true
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("") {
                viewModel.selectedTab?.reload()
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("") {
                viewModel.selectedTab?.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)

            Button("") {
                viewModel.selectedTab?.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)

            Button("") {
                toggleFindBar()
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("") {
                withAnimation(.snappy(duration: 0.2)) {
                    viewModel.selectNextTab()
                }
            }
            .keyboardShortcut(KeyEquivalent("}"), modifiers: [.command, .shift])

            Button("") {
                withAnimation(.snappy(duration: 0.2)) {
                    viewModel.selectPreviousTab()
                }
            }
            .keyboardShortcut(KeyEquivalent("{"), modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)

        Group {
            Button("") {
                if let tab = viewModel.selectedTab, let url = tab.currentURL {
                    viewModel.bookmarkStore.toggleBookmark(title: tab.title, url: url)
                }
            }
            .keyboardShortcut("d", modifiers: .command)

            Button("") {
                selectedCollectionTab = .history
                showBookmarks = true
            }
            .keyboardShortcut("y", modifiers: .command)

            Button("") {
                withAnimation(.snappy(duration: 0.25)) {
                    viewModel.reopenLastClosedTab()
                }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button("") {
                viewModel.selectedTab?.zoomIn()
            }
            .keyboardShortcut("=", modifiers: .command)

            Button("") {
                viewModel.selectedTab?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("") {
                viewModel.selectedTab?.resetZoom()
            }
            .keyboardShortcut("0", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
    }

    // MARK: - Browser View

    private var addressBarOnTop: Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular || verticalSizeClass == .compact
        #else
        return true
        #endif
    }

    private var browserView: some View {
        ZStack(alignment: .bottom) {
            contentArea
                #if os(iOS)
                .ignoresSafeArea(edges: .bottom)
                .ignoresSafeArea(edges: .top)
                #endif

            if !addressBarOnTop {
                bottomToolbarContainer
            }
        }
        .overlay(alignment: .top) {
            topBarContent
        }
        .animation(.snappy(duration: 0.25), value: showFindBar)
        .onChange(of: addressBarOnTop) { _, onTop in
            if onTop {
                viewModel.bottomBarHeight = 0
            } else {
                viewModel.topBarHeight = 0
            }
        }
    }

    private var topBarContent: some View {
        Group {
            if addressBarOnTop {
                VStack(spacing: 0) {
                    AnyView(addressBar)

                    if showFindBar {
                        findBar
                            .padding(.top, 2)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if shouldShowTabStrip && !isAddressBarFocused {
                        tabStrip
                            .padding(.top, 2)
                            .padding(.bottom, 6)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .background(
                    .ultraThinMaterial,
                    ignoresSafeAreaEdges: [.top, .horizontal]
                )
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.primary.opacity(0.06))
                        .frame(height: 0.5)
                        .ignoresSafeArea(edges: .horizontal)
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onChange(of: proxy.size.height) { _, newHeight in
                                if abs(viewModel.topBarHeight - newHeight) > 0.5 {
                                    viewModel.topBarHeight = newHeight
                                }
                            }
                            .onChange(of: proxy.size.width) { _, newWidth in
                                bottomContainerWidth = newWidth
                            }
                            .onAppear {
                                bottomContainerWidth = proxy.size.width
                                viewModel.bottomBarHeight = 0
                                viewModel.topBarHeight = proxy.size.height
                            }
                    }
                )
            } else {
                Group {
                    if shouldShowTabStrip && !isAddressBarFocused {
                        tabStrip
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.15), value: shouldShowTabStrip)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: isAddressBarFocused)
    }

    private var bottomToolbarContainer: some View {
        let expanded = isToolbarExpanded || isAddressBarFocused

        return VStack(spacing: 0) {
            if showFindBar {
                findBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            AnyView(addressBar)
        }
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear.onChange(of: proxy.size.height) { _, newHeight in
                    if expanded && abs(viewModel.bottomBarHeight - newHeight) > 0.5 {
                        viewModel.bottomBarHeight = newHeight
                    }
                }
                .onChange(of: proxy.size.width) { _, newWidth in
                    bottomContainerWidth = newWidth
                }
                .onAppear {
                    bottomContainerWidth = proxy.size.width
                    if expanded {
                        viewModel.bottomBarHeight = proxy.size.height
                    }
                }
            }
        )
    }

    // MARK: - Tab Strip

    private var tabStrip: some View {
        let tabCount = max(1, viewModel.tabs.count)
        let staticSpace: CGFloat = 6.0
        let availableTabSpace = max(0, bottomContainerWidth - staticSpace)
        let totalSpacing = CGFloat(max(0, tabCount - 1)) * 0.0
        let calculatedWidth = max(100, (availableTabSpace - totalSpacing) / CGFloat(tabCount))

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(viewModel.tabs.enumerated()), id: \.element.id) { index, tab in
                        tabChip(for: tab, tabWidth: calculatedWidth, index: index)
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 3)
            }
            .coordinateSpace(name: "tabStripScroll")
            .clipShape(Capsule())
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 10)
        }
    }

    private func tabChip(for tab: BrowserTab, tabWidth: CGFloat, index: Int) -> some View {
        let isSelected = tab.id == viewModel.selectedTabID
        let isLast = index == viewModel.tabs.count - 1
        let nextIsSelected = !isLast && viewModel.tabs[index + 1].id == viewModel.selectedTabID

        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                viewModel.selectTab(tab.id)
            }
        } label: {
            HStack(spacing: 5) {


                Spacer(minLength: 0)

                if tab.currentURL != nil {
                    favicon(for: tab, size: 14)
                } else if tab.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14, height: 14)
                }

                Text(tab.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            viewModel.closeTab(tab.id)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                            .background(
                                Circle().fill(Color.primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, isSelected ? 4 : 8)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            .frame(width: tabWidth)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
                        .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
                }
            }
            .overlay(alignment: .trailing) {
                if !isLast && !isSelected && !nextIsSelected {
                    Rectangle()
                        .fill(.primary.opacity(0.35))
                        .frame(width: 1.5)
                        .padding(.vertical, 8)
                }
            }
        }
        .buttonStyle(.plain)
        .id(tab.id)
        .zIndex(isSelected ? 10 : 0)
        .visualEffect { content, proxy in
            let offset: CGFloat = {
                guard isSelected else { return 0 }
                let frame = proxy.frame(in: .named("tabStripScroll"))
                let visibleWidth = max(0, bottomContainerWidth - 20)
                let edgePadding: CGFloat = 3
                
                if frame.minX < edgePadding {
                    return edgePadding - frame.minX
                } else if frame.maxX > visibleWidth - edgePadding {
                    return (visibleWidth - edgePadding) - frame.maxX
                }
                return 0
            }()
            
            return content.offset(x: offset)
        }
        .contextMenu {
            if let url = tab.currentURL {
                Button {
                    UIPasteboard.general.string = url.absoluteString
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
                
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            
            Divider()

            if viewModel.tabs.count > 1 {
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        viewModel.closeOtherTabs(tab.id)
                    }
                } label: {
                    Label("Close Other Tabs", systemImage: "xmark.square")
                }
            }
            
            Button(role: .destructive) {
                withAnimation(.snappy(duration: 0.25)) {
                    viewModel.closeTab(tab.id)
                }
            } label: {
                Label("Close Tab", systemImage: "xmark")
            }
        }
    }

    // MARK: - Address Bar

    private func displayHost(for text: String) -> String {
        guard let url = URL(string: text), let host = url.host() else {
            return text.isEmpty ? "Search" : text
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var selectedTabIndex: Int? {
        guard let selectedTabID = viewModel.selectedTabID else { return nil }
        return viewModel.tabs.firstIndex(where: { $0.id == selectedTabID })
    }

    private var swipePreviewDirection: SwipePreviewDirection? {
        guard !isAddressBarFocused else { return nil }
        if addressBarOffset > 0 { return .previous }
        if addressBarOffset < 0 { return .next }
        return nil
    }

    private func previewTab(for direction: SwipePreviewDirection) -> BrowserTab? {
        guard let selectedTabIndex else { return nil }

        switch direction {
        case .previous:
            guard selectedTabIndex > 0 else { return nil }
            return viewModel.tabs[selectedTabIndex - 1]
        case .next:
            let nextIndex = selectedTabIndex + 1
            guard nextIndex < viewModel.tabs.count else { return nil }
            return viewModel.tabs[nextIndex]
        }
    }

    private func shouldPreviewNewTab(for direction: SwipePreviewDirection) -> Bool {
        guard direction == .next,
              let selectedTabIndex,
              viewModel.selectedTab?.currentURL != nil
        else { return false }
        return selectedTabIndex == viewModel.tabs.count - 1
    }

    private var canCreateNewTabBySwipe: Bool {
        guard let selectedTab = viewModel.selectedTab else { return false }
        return selectedTab.currentURL != nil
    }

    private func addressLabel(for tab: BrowserTab?) -> String {
        guard let tab else { return "New Tab" }
        if let url = tab.currentURL?.absoluteString {
            return displayHost(for: url)
        }
        return tab.isPrivate ? "Private Search" : "New Tab"
    }

    private func addressIconName(for tab: BrowserTab?) -> String {
        tab?.currentURL != nil ? "lock.fill" : "magnifyingglass"
    }

    private func invalidSwipeFeedback() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    @ViewBuilder
    private func newTabButton(compact: Bool = false) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                viewModel.addNewTab()
            }
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: compact ? 12 : 13, weight: .bold))
                .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)
                .background(
                    Circle()
                        .fill(Color.accentColor.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var addressBar: some View {
        let expanded = isToolbarExpanded || isAddressBarFocused

        return GlassEffectContainer(spacing: 0) { HStack(spacing: 8) {
            if isAddressBarFocused && addressBarOnTop {
                // Spacer to balance the close button on the right for centering
                Spacer()
                    .frame(width: 32 + 8) // xmark frame width (32) + HStack spacing (8)
                    .allowsHitTesting(false)
            }

            if expanded && !isAddressBarFocused {
                HStack(spacing: 0) {


                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        viewModel.selectedTab?.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .disabled(!(viewModel.selectedTab?.canGoBack ?? false))

                    if viewModel.selectedTab?.canGoForward == true {
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            viewModel.selectedTab?.goForward()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .transition(.asymmetric(insertion: .scale(scale: 0.001, anchor: .leading).combined(with: .opacity), removal: .scale(scale: 0.001, anchor: .leading).combined(with: .opacity)))
                    }

                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)

                if horizontalSizeClass != .compact {
                    Button {
                        selectedCollectionTab = .bookmarks
                        showBookmarks = true
                    } label: {
                        Image(systemName: "book")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .glassEffect(.regular, in: .capsule)
                }
            }

            ZStack {
                let previewDirection = swipePreviewDirection
                let previewTab = previewDirection.flatMap(previewTab(for:))
                let previewShowsNewTab = previewDirection.map(shouldPreviewNewTab(for:)) ?? false
                let previewProgress = min(abs(addressBarOffset) / max(addressBarWidth, 1), CGFloat(1))
                let previewBaseOffset = addressBarWidth == 0 ? 0 : (previewDirection == .previous ? -addressBarWidth : addressBarWidth)

                if previewDirection != nil {
                    Group {
                        if expanded {
                            HStack(spacing: 8) {
                                Image(systemName: addressIconName(for: previewTab))
                                    .foregroundStyle(Color.secondary.opacity(0.9))
                                    .font(.system(size: 15, weight: .medium))
                                    .frame(width: 18)

                                Text(previewShowsNewTab ? "Search or enter website name" : addressLabel(for: previewTab))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(previewShowsNewTab ? .secondary : .primary)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                if previewShowsNewTab {
                                    newTabButton()
                                } else if let previewTab, previewTab.currentURL != nil {
                                    Image(systemName: previewTab.isLoading ? "xmark" : "arrow.clockwise")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 14, weight: .medium))
                                }
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: addressIconName(for: previewTab))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(previewShowsNewTab ? "New Tab" : addressLabel(for: previewTab))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                if previewShowsNewTab {
                                    Spacer(minLength: 0)
                                    newTabButton(compact: true)
                                }
                            }
                        }
                    }
                    .offset(x: previewBaseOffset + addressBarOffset)
                    .opacity(previewProgress)
                    .scaleEffect(CGFloat(0.985) + (previewProgress * CGFloat(0.015)))
                    .allowsHitTesting(false)
                }

                HStack(spacing: 8) {
                    Image(systemName: isAddressBarFocused
                          ? "magnifyingglass"
                          : (viewModel.selectedTab?.currentURL != nil ? "lock.fill" : (viewModel.isPrivate ? "eye.slash.fill" : "magnifyingglass")))
                        .foregroundStyle(viewModel.isPrivate && !isAddressBarFocused ? .purple : Color.secondary)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 18)
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.easeInOut(duration: 0.2), value: isAddressBarFocused)

                    TextField("Search or enter website name", text: $addressText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .semibold))
                        .multilineTextAlignment(isAddressBarFocused ? .leading : .center)
                        .focused($isAddressBarFocused)
                        .onSubmit {
                            submitAddressBarText(addressText)
                        }
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.webSearch)
                        #endif
                        .autocorrectionDisabled()

                    if isAddressBarFocused && !addressText.isEmpty {
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            addressText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .font(.system(size: 15))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    } else if let tab = viewModel.selectedTab, tab.currentURL != nil, !isAddressBarFocused {
                        HStack(spacing: 12) {
                            Button {
                                if tab.isLoading { tab.stopLoading() } else { tab.reload() }
                            } label: {
                                Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 14, weight: .medium))
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(.plain)
                        }
                        .transition(.opacity)
                    }
                }
                .offset(x: addressBarOffset)
                .frame(maxWidth: expanded ? .infinity : 0.001)
                .clipped()
                .opacity(expanded ? Double(CGFloat(1) - (previewProgress * CGFloat(0.18))) : 0)
                .allowsHitTesting(expanded)

                HStack(spacing: 4) {
                    Image(systemName: viewModel.selectedTab?.currentURL != nil ? "lock.fill" : (viewModel.isPrivate ? "eye.slash.fill" : "magnifyingglass"))
                        .font(.system(size: 10))
                        .foregroundStyle(viewModel.isPrivate ? .purple : .secondary)
                    Text(displayHost(for: addressText))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .offset(x: addressBarOffset)
                .opacity(expanded ? 0 : Double(CGFloat(1) - (previewProgress * CGFloat(0.18))))
                .allowsHitTesting(!expanded)
            }
            .padding(.horizontal, expanded ? 16 : 10)
            .padding(.vertical, expanded ? 12 : 5)
            .frame(maxWidth: expanded ? .infinity : 160)
            .glassEffect(.regular, in: .capsule)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            addressBarWidth = proxy.size.width
                        }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            addressBarWidth = newWidth
                        }
                }
            }
            .overlay(alignment: .bottom) {
                ZStack {
                    if let tab = viewModel.selectedTab, tab.isLoading {
                        GeometryReader { geo in
                            let barHeight: CGFloat = 4
                            let barInset: CGFloat = 18
                            let trackWidth = max(0, geo.size.width - barInset * 2)
                            let p = min(1, max(0, tab.estimatedProgress))
                            let progressWidth = max(15, trackWidth * max(0.03, p))

                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.blue.opacity(0.12))

                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .cyan],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: min(trackWidth, progressWidth))
                                    .shadow(color: .cyan.opacity(0.4), radius: 2, y: 0)
                            }
                            .frame(height: barHeight)
                            .padding(.horizontal, barInset)
                            .offset(y: 2)
                        }
                        .frame(height: 4)
                        .allowsHitTesting(false)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -5)),
                                removal: .opacity
                            )
                        )
                    }
                }
                .animation(
                    .interactiveSpring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.12),
                    value: viewModel.selectedTab?.estimatedProgress
                )
                .animation(
                    .spring(response: 0.38, dampingFraction: 0.88),
                    value: viewModel.selectedTab?.isLoading
                )
            }
            .contextMenu {
                if let url = viewModel.selectedTab?.currentURL {
                    Button {
                        UIPasteboard.general.string = url.absoluteString
                    } label: {
                        Label("Copy Link", systemImage: "link")
                    }
                    
                    ShareLink(item: url) {
                        Label("Share...", systemImage: "square.and.arrow.up")
                    }
                }
                
                Button {
                    if let pasted = UIPasteboard.general.string {
                        viewModel.selectedTab?.loadRequest(pasted)
                        isAddressBarFocused = false
                    }
                } label: {
                    Label("Paste and Search", systemImage: "doc.on.clipboard")
                }
                
                if let tab = viewModel.selectedTab {
                    Button(role: .destructive) {
                        withAnimation {
                            viewModel.closeTab(tab.id)
                        }
                    } label: {
                        Label("Close Tab", systemImage: "xmark")
                    }
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        if isAddressBarFocused { return }
                        if abs(value.translation.width) > abs(value.translation.height) {
                            let resistance = min(abs(value.translation.width) / 1200, 0.1)
                            let easedTranslation = value.translation.width * (1 - resistance)
                            addressBarOffset += (easedTranslation - addressBarOffset) * 0.34
                            addressBarVerticalOffset = 0
                        } else if value.translation.height < 0 {
                            let resistance = min(abs(value.translation.height) / 1000, 0.2)
                            let easedTranslation = value.translation.height * (1 - resistance)
                            addressBarVerticalOffset += (easedTranslation - addressBarVerticalOffset) * 0.7
                            addressBarOffset = 0
                        }
                    }
                    .onEnded { value in
                        if isAddressBarFocused { return }

                        if value.translation.height < -30 || value.predictedEndTranslation.height < -100 {
                            if abs(value.translation.height) > abs(value.translation.width) {
                                #if os(iOS)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                #endif
                                viewModel.snapshotAllTabs()
                                withAnimation(.spring(duration: 0.45, bounce: 0.12)) {
                                    showTabOverview = true
                                    addressBarVerticalOffset = 0
                                }
                                return
                            }
                        }

                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                            addressBarVerticalOffset = 0
                        }

                        let projectedWidth = value.predictedEndTranslation.width
                        let translation = value.translation.width
                        let transitionWidth = max(addressBarWidth, 320)
                        let triggerDistance = max(addressBarWidth * 0.18, 56)
                        let canSwipeBackward = (selectedTabIndex ?? 0) > 0
                        let canSwipeForward = canCreateNewTabBySwipe || ((selectedTabIndex ?? -1) < (viewModel.tabs.count - 1))
    
                        if translation > triggerDistance || projectedWidth > triggerDistance * 1.35 {
                            guard canSwipeBackward else {
                                invalidSwipeFeedback()
                                withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.9)) {
                                    addressBarOffset = 0
                                }
                                return
                            }
                            #if os(iOS)
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            #endif
                            withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.94)) {
                                addressBarOffset = transitionWidth
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                viewModel.selectPreviousTab()
                                addressBarOffset = -transitionWidth * 0.18
                                withAnimation(.interactiveSpring(response: 0.46, dampingFraction: 0.9)) {
                                    addressBarOffset = 0
                                }
                            }
                        } else if translation < -triggerDistance || projectedWidth < -triggerDistance * 1.35 {
                            guard canSwipeForward else {
                                invalidSwipeFeedback()
                                withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.9)) {
                                    addressBarOffset = 0
                                }
                                return
                            }
                            #if os(iOS)
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            #endif
                            withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.94)) {
                                addressBarOffset = -transitionWidth
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                viewModel.selectNextTab()
                                addressBarOffset = transitionWidth * 0.18
                                withAnimation(.interactiveSpring(response: 0.46, dampingFraction: 0.9)) {
                                    addressBarOffset = 0
                                }
                            }
                        } else {
                            withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.9)) {
                                addressBarOffset = 0
                            }
                        }
                    }
            )

            if expanded && !isAddressBarFocused {
                HStack(spacing: 6) {
                    Menu {
                        moreMenuItems
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if horizontalSizeClass != .compact {
                        if let url = viewModel.selectedTab?.currentURL {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .medium))
                                    .frame(width: 36, height: 36)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            withAnimation(.snappy(duration: 0.25)) {
                                viewModel.addNewTab()
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            viewModel.snapshotAllTabs()
                            withAnimation(.spring(duration: 0.45, bounce: 0.12)) {
                                showTabOverview = true
                            }
                        } label: {
                            Image(systemName: "square.on.square")
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
            }

            if isAddressBarFocused {
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    isAddressBarFocused = false
                    addressText = viewModel.selectedTab?.currentURL?.absoluteString ?? ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .clipShape(Circle())
                .transition(.move(edge: .trailing).combined(with: .scale))
            }
        } }
        .padding(.horizontal, 12)
        .padding(.top, expanded ? 8 : (addressBarOnTop ? 8 : 4))
        .padding(.bottom, expanded ? 4 : (addressBarOnTop ? 6 : 2))
        .frame(maxWidth: isAddressBarFocused && addressBarOnTop ? 720 : .infinity)
        .frame(maxWidth: .infinity)
        .background {
            if !expanded {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                            viewModel.selectedTab?.toolbarVisible = true
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.15), value: isAddressBarFocused)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: expanded)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: viewModel.selectedTab?.canGoForward)
    }

    private var tabOverviewButton: some View {
        Button {
            viewModel.snapshotAllTabs()
            withAnimation(.spring(duration: 0.45, bounce: 0.12)) {
                showTabOverview.toggle()
            }
        } label: {
            Image(systemName: "square.on.square")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    // MARK: - More Menu

    @ViewBuilder
    private var moreMenuItems: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            Button {
                viewModel.snapshotAllTabs()
                withAnimation(.spring(duration: 0.45, bounce: 0.12)) {
                    showTabOverview = true
                }
            } label: {
                Label("Tab Overview", systemImage: "square.on.square")
            }

            if let tab = viewModel.selectedTab, let url = tab.currentURL {
                ShareLink(item: url) {
                    Label("Share...", systemImage: "square.and.arrow.up")
                }
            }
            Divider()
        }
        #endif

        if let tab = viewModel.selectedTab, let url = tab.currentURL {
            Button {
                viewModel.bookmarkStore.toggleBookmark(title: tab.title, url: url)
            } label: {
                Label(
                    viewModel.bookmarkStore.isBookmarked(url) ? "Remove Bookmark" : "Add Bookmark",
                    systemImage: viewModel.bookmarkStore.isBookmarked(url) ? "star.fill" : "star"
                )
            }

            let isFavorited = viewModel.favoriteStore.favorites.contains { $0.url == url }
            Button {
                if isFavorited {
                    if let fav = viewModel.favoriteStore.favorites.first(where: { $0.url == url }) {
                        viewModel.favoriteStore.removeFavorite(id: fav.id)
                    }
                } else {
                    viewModel.favoriteStore.addFavorite(title: tab.title, url: url)
                }
            } label: {
                Label(
                    isFavorited ? "Remove Favorite" : "Add Favorite",
                    systemImage: isFavorited ? "heart.fill" : "heart"
                )
            }

            Divider()
        }

        Button {
            selectedCollectionTab = .bookmarks
            showBookmarks = true
        } label: {
            Label("Bookmarks", systemImage: "book")
        }

        Button {
            selectedCollectionTab = .history
            showBookmarks = true
        } label: {
            Label("History", systemImage: "clock.arrow.circlepath")
        }

        Button { showSettings = true } label: {
            Label("Settings", systemImage: "gear")
        }

        if viewModel.selectedTab?.currentURL != nil {
            Divider()

            Button { viewModel.selectedTab?.zoomIn() } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }

            Button { viewModel.selectedTab?.zoomOut() } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }

            if viewModel.selectedTab?.zoomLevel != 1.0 {
                Button { viewModel.selectedTab?.resetZoom() } label: {
                    let pct = Int((viewModel.selectedTab?.zoomLevel ?? 1.0) * 100)
                    Label("Actual Size (\(pct)%)", systemImage: "1.magnifyingglass")
                }
            }
        }

        Divider()

        #if os(iOS)
        if viewModel.selectedTab?.currentURL != nil {
            Button {
                viewModel.selectedTab?.toggleDesktopMode()
            } label: {
                Label(
                    viewModel.selectedTab?.isDesktopMode == true ? "Request Mobile Site" : "Request Desktop Site",
                    systemImage: viewModel.selectedTab?.isDesktopMode == true ? "iphone" : "desktopcomputer"
                )
            }
        }
        #endif

        Button {
            withAnimation(.snappy(duration: 0.25)) {
                viewModel.duplicateSelectedTab()
            }
        } label: {
            Label("Duplicate Tab", systemImage: "plus.square.on.square")
        }
        .disabled(viewModel.selectedTab?.currentURL == nil)

        if viewModel.canReopenTab {
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    viewModel.reopenLastClosedTab()
                }
            } label: {
                Label("Reopen Closed Tab", systemImage: "arrow.uturn.forward")
            }
        }
    }

    #if !os(iOS)
    private var moreMenuDesktop: some View {
        Menu {
            moreMenuItems
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: - Find Bar

    private var findBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 11))

                TextField("Find on page", text: $findText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isFindBarFocused)
                    .onSubmit {
                        viewModel.selectedTab?.findInPageNext()
                    }
                    .onChange(of: findText) {
                        viewModel.selectedTab?.findInPage(findText)
                    }

                if !findText.isEmpty {
                    Button {
                        findText = ""
                        viewModel.selectedTab?.clearFind()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)

            HStack(spacing: 2) {
                Button {
                    viewModel.selectedTab?.findInPagePrevious()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(findText.isEmpty)

                Button {
                    viewModel.selectedTab?.findInPageNext()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(findText.isEmpty)
            }

            Button("Done") {
                dismissFindBar()
            }
            .font(.system(size: 12, weight: .medium))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: - Content Area

    private var contentArea: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                let currentIndex = viewModel.tabs.firstIndex(where: { $0.id == viewModel.selectedTabID }) ?? 0
                
                ForEach(Array(viewModel.tabs.enumerated()), id: \.element.id) { index, tab in
                    let difference = CGFloat(index - currentIndex)
                    let spacing: CGFloat = 32
                    let offset = (difference * (geo.size.width + spacing)) + addressBarOffset
                    let distance = min(abs(offset) / max(geo.size.width, 1), CGFloat(1.1))
                    
                    let hScale = 1.0 - (min(distance, 1.0) * 0.05)
                    let hRounding = min(distance * 60, 1.0) * 38
                    
                    let yOffset = addressBarVerticalOffset
                    let vRoundingProgress = min(max(-yOffset / 15, 0), 1.0)
                    let vScaleProgress = min(max(-yOffset / 160, 0), 1.0)
                    
                    let vScale = 1.0 - (vScaleProgress * 0.25)
                    let vRounding = vRoundingProgress * 38
                    
                    let finalScale = hScale * vScale
                    let finalRounding = max(hRounding, vRounding)

                    if abs(offset) <= geo.size.width * 1.5 {
                        Group {
                            if tab.currentURL != nil {
                                WebView(tab: tab, bottomBarHeight: viewModel.bottomBarHeight, topBarHeight: viewModel.topBarHeight)
                                    .id(tab.id)
                            } else {
                                startPage
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: finalRounding, style: .continuous))
                        .shadow(color: Color.black.opacity(0.4 * max(min(distance * 40, 1.0), vRoundingProgress)), radius: 45, x: 0, y: 0)
                        .scaleEffect(finalScale)
                        .offset(x: offset, y: yOffset * 0.5)
                        .opacity(Double(CGFloat(1) - (max(distance, vScaleProgress * 0.5) * CGFloat(0.04))))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()

            if showStartPageOverlay && !addressBarOnTop {
                ZStack {
                    Rectangle()
                        .fill(.black.opacity(0.12))
                    Rectangle()
                        .fill(.ultraThinMaterial)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea()
                .transition(.opacity)

                startPage
                    .frame(width: geo.size.width, height: geo.size.height)
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.96, anchor: .bottom))
                                .combined(with: .offset(y: 24)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.97, anchor: .center))
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .clipped()
        .animation(.interactiveSpring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.18), value: addressBarOffset)
        .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.88, blendDuration: 0.18), value: viewModel.selectedTabID)
    }

    private var floatingStartPageOverlay: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Invisible gap to keep address bar accessible
                Color.clear
                    .frame(height: viewModel.topBarHeight)
                    .allowsHitTesting(false)
                
                // Floating liquid glass window
                ZStack(alignment: .top) {
                    startPage
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                }
                .frame(maxWidth: 760)
                .frame(maxHeight: 680)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: .black.opacity(0.26), radius: 60, x: 0, y: 25)
                .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 10)
                .overlay {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
                .frame(width: addressBarWidth > 0 ? addressBarWidth : 720)
                .frame(maxHeight: 680)
                .padding(.top, 12)
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .offset(y: -20))
                            .combined(with: .scale(scale: 0.98)),
                        removal: .opacity
                            .combined(with: .scale(scale: 0.985))
                    )
                )
            }
        }
        .ignoresSafeArea(.keyboard)
        .zIndex(100)
    }

    // MARK: - Autocomplete Suggestions

    private enum AutocompleteSection: String {
        case recent = "Recent Searches"
        case google = "Google Suggestions"
        case local = "Bookmarks, History and Tabs"
    }

    private enum AutocompleteSuggestionKind {
        case localURL(URL)
        case googleQuery(String)
    }

    private struct AutocompleteSuggestion: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let iconColor: Color
        let kind: AutocompleteSuggestionKind
        let section: AutocompleteSection
    }

    private var localAutocompleteSuggestions: [AutocompleteSuggestion] {
        let query = addressText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty, isAddressBarFocused else { return [] }

        var results: [AutocompleteSuggestion] = []
        var seenURLs = Set<String>()

        // Prioritize currently open tabs so they are always visible in suggestions.
        for tab in viewModel.tabs {
            guard let url = tab.currentURL else { continue }
            let key = url.absoluteString.lowercased()
            if tab.title.localizedCaseInsensitiveContains(query) || key.localizedCaseInsensitiveContains(query) {
                seenURLs.insert(key)
                results.append(.init(
                    title: tab.title,
                    subtitle: "Open tab • \(url.host ?? url.absoluteString)",
                    icon: "square.on.square",
                    iconColor: .purple,
                    kind: .localURL(url),
                    section: .local
                ))
            }
            if results.count >= 6 { break }
        }

        for bookmark in viewModel.bookmarkStore.bookmarks {
            let key = bookmark.url.absoluteString.lowercased()
            guard !seenURLs.contains(key) else { continue }
            if bookmark.title.localizedCaseInsensitiveContains(query) ||
               bookmark.url.absoluteString.localizedCaseInsensitiveContains(query) {
                seenURLs.insert(key)
                results.append(.init(
                    title: bookmark.title,
                    subtitle: bookmark.url.host ?? bookmark.url.absoluteString,
                    icon: "bookmark.fill",
                    iconColor: .orange,
                    kind: .localURL(bookmark.url),
                    section: .local
                ))
            }
            if results.count >= 12 { break }
        }

        for favorite in viewModel.favoriteStore.favorites {
            let key = favorite.url.absoluteString.lowercased()
            guard !seenURLs.contains(key) else { continue }
            if favorite.title.localizedCaseInsensitiveContains(query) ||
               favorite.url.absoluteString.localizedCaseInsensitiveContains(query) {
                seenURLs.insert(key)
                results.append(.init(
                    title: favorite.title,
                    subtitle: favorite.url.host ?? favorite.url.absoluteString,
                    icon: "bookmark.fill",
                    iconColor: .orange,
                    kind: .localURL(favorite.url),
                    section: .local
                ))
            }
            if results.count >= 12 { break }
        }

        for entry in viewModel.historyStore.entries {
            let key = entry.url.absoluteString.lowercased()
            guard !seenURLs.contains(key) else { continue }
            if entry.title.localizedCaseInsensitiveContains(query) ||
               entry.url.absoluteString.localizedCaseInsensitiveContains(query) {
                seenURLs.insert(key)
                results.append(.init(
                    title: entry.title,
                    subtitle: entry.url.host ?? entry.url.absoluteString,
                    icon: "clock.fill",
                    iconColor: .blue,
                    kind: .localURL(entry.url),
                    section: .local
                ))
            }
            if results.count >= 12 { break }
        }

        return Array(results.prefix(12))
    }

    private var recentSearchSuggestions: [AutocompleteSuggestion] {
        recentSearchQueries.prefix(10).map { query in
            .init(
                title: query,
                subtitle: "Recent search",
                icon: "magnifyingglass",
                iconColor: .secondary,
                kind: .googleQuery(query),
                section: .recent
            )
        }
    }

    private var googleSuggestionItems: [AutocompleteSuggestion] {
        let query = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var items: [AutocompleteSuggestion] = []
        var seenTitles = Set<String>()

        for suggestion in googleAutocompleteQueries {
            let normalized = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            guard !seenTitles.contains(key) else { continue }
            seenTitles.insert(key)
            items.append(.init(
                title: normalized,
                subtitle: "Google suggestion",
                icon: "magnifyingglass",
                iconColor: .blue,
                kind: .googleQuery(normalized),
                section: .google
            ))
        }

        if items.isEmpty, !query.isEmpty {
            items.append(.init(
                title: query,
                subtitle: "Search with Google",
                icon: "magnifyingglass",
                iconColor: .blue,
                kind: .googleQuery(query),
                section: .google
            ))
        }

        return Array(items.prefix(6))
    }

    private var autocompleteSuggestions: [AutocompleteSuggestion] {
        let query = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return recentSearchSuggestions
        }
        return googleSuggestionItems + localAutocompleteSuggestions
    }

    private var shouldShowAutocompleteOverlay: Bool {
        guard isAddressBarFocused, !showTabOverview else { return false }
        let query = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return !recentSearchSuggestions.isEmpty
        }
        return hasEditedAddressTextSinceFocus && !autocompleteSuggestions.isEmpty
    }

    /// Portrait + bottom address bar: use a small top gap instead of full safe-area inset so more room for results.
    private func autocompletePortraitTopGap(_ safeTop: CGFloat) -> CGFloat {
        #if os(iOS)
        min(max(safeTop * 0.28, 6), 16)
        #else
        safeTop
        #endif
    }

    /// Bottom chrome height so autocomplete stays above the address bar in portrait (not only above the keyboard).
    private var autocompleteBottomChromeInset: CGFloat {
        #if os(iOS)
        if addressBarOnTop {
            return 0
        }
        let expanded = isToolbarExpanded || isAddressBarFocused
        let h = viewModel.bottomBarHeight
        if expanded, h > 0.5 { return h }
        return max(h, isAddressBarFocused ? 76 : 56)
        #else
        return 0
        #endif
    }

    private var autocompleteFloatingLayer: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: addressBarOnTop ? (viewModel.topBarHeight + 6) : autocompletePortraitTopGap(proxy.safeAreaInsets.top))

                autocompleteSuggestionsList
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.bottom, autocompleteBottomChromeInset)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .allowsHitTesting(true)
    }

    private var autocompleteSuggestionsList: some View {
        let query = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        let grouped = Dictionary(grouping: autocompleteSuggestions, by: \.section)
        let order: [AutocompleteSection] = query.isEmpty ? [.recent] : [.google, .local]

        return List {
            ForEach(order, id: \.rawValue) { section in
                if let items = grouped[section], !items.isEmpty {
                    HStack {
                        Text(section.rawValue)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.tertiary)

                        Spacer(minLength: 0)

                        if section == .recent {
                            Button("Clear") {
                                withAnimation {
                                    recentSearchQueries = []
                                    saveRecentSearches()
                                }
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
                    .padding(.top, section == order.first ? 0 : 8)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    ForEach(items) { suggestion in
                        autocompleteRow(suggestion)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 8)
        .animation(.spring(duration: 0.35, bounce: 0.14), value: autocompleteSuggestions.map(\.title))
    }

    @ViewBuilder
    private func autocompleteRow(_ suggestion: AutocompleteSuggestion) -> some View {
        let row = Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            switch suggestion.kind {
            case .localURL(let url):
                viewModel.selectedTab?.load(url)
            case .googleQuery(let query):
                recordRecentSearch(query)
                if let googleURL = SearchEngine.google.searchURL(query: query) {
                    viewModel.selectedTab?.load(googleURL)
                }
            }
            isAddressBarFocused = false
        } label: {
            HStack(spacing: 12) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(suggestion.iconColor)
                    .frame(width: 28, height: 28)
                    .background(suggestion.iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(suggestion.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if suggestion.section == .recent {
            row
                .contextMenu {
                    Button(role: .destructive) {
                        deleteRecentSearch(suggestion.title)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        withAnimation {
                            deleteRecentSearch(suggestion.title)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        } else {
            row
        }
    }

    private func deleteRecentSearch(_ query: String) {
        recentSearchQueries.removeAll { $0 == query }
        saveRecentSearches()
    }

    private func fetchGoogleAutocompleteSuggestions(for text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAddressBarFocused, hasEditedAddressTextSinceFocus, !query.isEmpty else {
            googleSuggestTask?.cancel()
            googleAutocompleteQueries = []
            return
        }

        googleSuggestTask?.cancel()
        googleSuggestTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            let suggestions = await requestGoogleSuggestions(query: query)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if addressText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == query.lowercased() {
                    googleAutocompleteQueries = suggestions
                }
            }
        }
    }

    private func requestGoogleSuggestions(query: String) async -> [String] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://suggestqueries.google.com/complete/search?client=firefox&q=\(encoded)") else {
            return []
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                  json.count > 1,
                  let list = json[1] as? [String] else {
                return []
            }
            return Array(list.prefix(6))
        } catch {
            return []
        }
    }

    private func submitAddressBarText(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isLikelySearchQuery(trimmed) {
            recordRecentSearch(trimmed)
        }
        viewModel.selectedTab?.loadRequest(trimmed, engine: viewModel.searchEngine)
        isAddressBarFocused = false
    }

    private func isLikelySearchQuery(_ text: String) -> Bool {
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return false }
        if text.contains(" ") { return true }
        if !text.contains(".") { return true }
        return false
    }

    private func recordRecentSearch(_ query: String) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        recentSearchQueries.removeAll { $0.caseInsensitiveCompare(normalized) == .orderedSame }
        recentSearchQueries.insert(normalized, at: 0)
        recentSearchQueries = Array(recentSearchQueries.prefix(20))
        saveRecentSearches()
    }

    private func loadRecentSearches() {
        recentSearchQueries = UserDefaults.standard.stringArray(forKey: recentSearchesDefaultsKey) ?? []
    }

    private func saveRecentSearches() {
        UserDefaults.standard.set(recentSearchQueries, forKey: recentSearchesDefaultsKey)
    }

    // MARK: - Start Page

    private enum StartPageSectionSpacing {
        /// Space above each section card (after quick actions or following another section).
        static let beforeCard: CGFloat = 12
    }

    private var startPage: some View {
        let settings = viewModel.startPageSettings
        return ZStack {
            startPageBackground

            ScrollView {
                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 0) {
                        Spacer(minLength: startPageTopPadding)

                        if isCompactStartPage {
                            // Portrait: greeting card + quick actions share the same horizontal inset and width.
                            VStack(spacing: 12) {
                                if settings.showGreeting {
                                    startPageGreetingContent(large: true)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .padding(.horizontal, 18)
                                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                                        }
                                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                                }

                                startPageQuickActions
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, !settings.showGreeting && settings.showQuickActions ? 8 : 0)
                        } else {
                            // Landscape / iPad / macOS: greeting card and quick bar share the same max width when both show.
                            HStack(alignment: .center, spacing: 16) {
                                if settings.showGreeting {
                                    startPageGreetingContent(large: false)
                                        .frame(maxWidth: startPageLandscapeGreetingCardMaxWidth, alignment: .leading)
                                        .padding(.vertical, 11)
                                        .padding(.horizontal, startPageLandscapeGreetingHorizontalPadding)
                                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                                        }
                                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                                }

                                Spacer(minLength: 8)

                                startPageQuickActions
                                    .frame(maxWidth: settings.showGreeting ? startPageLandscapeGreetingCardOuterWidth : .infinity)
                            }
                            .padding(.horizontal, 20)
                        }

                        ForEach(settings.sectionOrder) { section in
                            startPageSectionView(for: section)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Customize button
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            showCustomizeStartPage = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Customize")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glassEffect(.regular, in: .capsule)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .padding(.top, StartPageSectionSpacing.beforeCard)

                        Spacer(minLength: 50)
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .animation(.spring(duration: 0.4, bounce: 0.15), value: settings.sectionOrder.map(\.rawValue))
                    .animation(.spring(duration: 0.35, bounce: 0.1), value: settings.showGreeting)
                }
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: viewModel.bottomBarHeight)
            }
            .safeAreaInset(edge: .top) {
                if !showStartPageOverlay || !addressBarOnTop {
                    Color.clear.frame(height: viewModel.topBarHeight)
                }
            }
        }
        .sheet(isPresented: $showCustomizeStartPage) {
            customizeStartPageSheet
        }
    }

    @ViewBuilder
    private func startPageGreetingContent(large: Bool) -> some View {
        VStack(spacing: large ? 4 : 3) {
            Text(greeting)
                .font(.system(size: large ? 26 : 20, weight: .bold, design: .rounded))
                .foregroundStyle(
                    .linearGradient(
                        colors: [startPageGradientColors.0, startPageGradientColors.1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(formattedDate)
                .font(.system(size: large ? 11 : 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(large ? 1.15 : 1.0)
        }
    }

    @ViewBuilder
    private func startPageSectionView(for section: StartPageSection) -> some View {
        let settings = viewModel.startPageSettings
        switch section {
        case .recentlyVisited:
            if settings.isSectionVisible(section) && !recentlyVisitedEntries.isEmpty {
                recentlyVisitedSection
            }
        case .bookmarks:
            if settings.isSectionVisible(section) && !viewModel.bookmarkStore.bookmarks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        sectionHeader("BOOKMARKS")
                        Spacer()
                        startPageSectionManageButton {
                            selectedCollectionTab = .bookmarks
                            showBookmarks = true
                        }
                    }

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: favoritesColumnCount),
                        spacing: 14
                    ) {
                        ForEach(viewModel.bookmarkStore.bookmarks.prefix(favoritesColumnCount * 2)) { bookmark in
                            bookmarkQuickLink(bookmark)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                }
                .padding(.horizontal, 20)
                .padding(.top, StartPageSectionSpacing.beforeCard)
            }
        case .favorites:
            if settings.isSectionVisible(section) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        sectionHeader("FAVORITES")
                        Spacer()
                        startPageSectionManageButton {
                            selectedCollectionTab = .favorites
                            showBookmarks = true
                        }
                    }

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: favoritesColumnCount),
                        spacing: 14
                    ) {
                        ForEach(viewModel.favoriteStore.favorites) { favorite in
                            quickLink(favorite.title, url: favorite.url.absoluteString)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                }
                .padding(.horizontal, 20)
                .padding(.top, StartPageSectionSpacing.beforeCard)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(.tertiary)
            .tracking(1.8)
    }

    private func startPageSectionManageButton(action: @escaping () -> Void) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .glassEffect(.regular, in: .circle)
        .accessibilityLabel("Manage")
    }

    private var customizeStartPageSheet: some View {
        let settings = viewModel.startPageSettings
        return NavigationStack {
            List {
                Section {
                    customizeToggle(
                        "Greeting",
                        icon: "sun.max.fill",
                        color: .orange,
                        isOn: Binding(get: { settings.showGreeting }, set: { settings.showGreeting = $0 })
                    )
                } header: {
                    Text("Header")
                }

                Section {
                    Picker("Preset", selection: Binding(
                        get: { settings.gradientPreset },
                        set: { settings.gradientPreset = $0 }
                    )) {
                        ForEach(StartPageGradientPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Background")
                }

                Section {
                    customizeToggle(
                        "Quick Actions",
                        icon: "bolt.fill",
                        color: .blue,
                        isOn: Binding(get: { settings.showQuickActions }, set: { settings.showQuickActions = $0 })
                    )

                    if settings.showQuickActions {
                        ForEach(settings.quickActionOrder) { item in
                            customizeToggle(
                                item.label,
                                icon: item.icon,
                                color: .secondary,
                                isOn: Binding(
                                    get: { settings.isQuickActionVisible(item) },
                                    set: { settings.setQuickActionVisible(item, $0) }
                                )
                            )
                        }
                        .onMove { from, to in
                            settings.moveQuickAction(from: from, to: to)
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }
                    }
                } header: {
                    HStack {
                        Text("Quick Actions")
                        Spacer()
                        if settings.showQuickActions {
                            Text("Drag to reorder")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .textCase(.none)
                        }
                    }
                }

                Section {
                    ForEach(settings.sectionOrder) { section in
                        customizeToggle(
                            section.label,
                            icon: section.icon,
                            color: section.color,
                            isOn: Binding(
                                get: { settings.isSectionVisible(section) },
                                set: { settings.setSectionVisible(section, $0) }
                            )
                        )
                    }
                    .onMove { from, to in
                        settings.moveSection(from: from, to: to)
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    }
                } header: {
                    HStack {
                        Text("Sections")
                        Spacer()
                        Text("Drag to reorder")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .textCase(.none)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customize Start Page")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showCustomizeStartPage = false
                    }
                    .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .sensoryFeedback(.selection, trigger: settings.sectionOrder.map(\.rawValue))
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func customizeToggle(_ title: String, icon: String, color: Color, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 8))

                Text(title)
                    .font(.system(size: 15, weight: .medium))
            }
        }
        .tint(color)
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
    }

    private var recentlyVisitedEntries: [HistoryEntry] {
        var seenHosts = Set<String>()
        var unique: [HistoryEntry] = []
        for entry in viewModel.historyStore.entries {
            let host = entry.url.host ?? entry.url.absoluteString
            if !seenHosts.contains(host) {
                seenHosts.insert(host)
                unique.append(entry)
            }
            if unique.count >= 8 { break }
        }
        return unique
    }

    private var recentlyVisitedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("RECENTLY VISITED")
                Spacer()
                startPageSectionManageButton {
                    selectedCollectionTab = .history
                    showBookmarks = true
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: favoritesColumnCount),
                spacing: 14
            ) {
                ForEach(recentlyVisitedEntries.prefix(favoritesColumnCount * 2)) { entry in
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        viewModel.selectedTab?.load(entry.url)
                        dismissStartPageOverlay()
                    } label: {
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.primary.opacity(0.04))
                                    .frame(width: 56, height: 56)
                                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))

                                Text(siteLetter(for: entry.url))
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .shadow(color: .black.opacity(0.06), radius: 10, y: 5)

                            Text(hostLabel(for: entry.url))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 66)
                        }
                    }
                    .buttonStyle(PressableButtonStyle())
                    .contextMenu {
                        startPageGridContextMenu(for: entry.url)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, StartPageSectionSpacing.beforeCard)
    }

    private func hostLabel(for url: URL) -> String {
        guard let host = url.host else { return url.absoluteString }
        let cleaned = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return cleaned.components(separatedBy: ".").first?.capitalized ?? cleaned
    }

    private var startPageAmbientBaseGradient: [Color] {
        #if os(iOS) || os(visionOS)
        [
            Color(uiColor: .secondarySystemBackground),
            Color(uiColor: .systemBackground)
        ]
        #elseif os(macOS)
        [
            Color(nsColor: .controlBackgroundColor),
            Color(nsColor: .windowBackgroundColor)
        ]
        #else
        [Color.gray.opacity(0.18), Color.gray.opacity(0.06)]
        #endif
    }

    private var startPageBackground: some View {
        Group {
            if showStartPageOverlay && addressBarOnTop {
                Color.clear
            } else {
                let (c1, c2) = startPageGradientColors
                ZStack {
            LinearGradient(
                colors: startPageAmbientBaseGradient,
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(0.35)

            // Primary ambient glow — top left
            RadialGradient(
                colors: [c1.opacity(0.38), c1.opacity(0.15), .clear],
                center: .topLeading,
                startRadius: 40,
                endRadius: 560
            )

            // Secondary ambient glow — bottom right
            RadialGradient(
                colors: [c2.opacity(0.34), c2.opacity(0.14), .clear],
                center: .bottomTrailing,
                startRadius: 30,
                endRadius: 520
            )

            // Soft center blend
            RadialGradient(
                colors: [c1.opacity(0.10), c2.opacity(0.09), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 420
            )

            // Subtle top-center highlight for depth
            RadialGradient(
                colors: [.white.opacity(0.06), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 340
            )

            // Liquid edge sheen
            RadialGradient(
                colors: [c1.opacity(0.12), .clear],
                center: .leading,
                startRadius: 0,
                endRadius: 280
            )
                }
                .ignoresSafeArea()
            }
        }
    }

    private var visibleQuickActionItems: [QuickActionItem] {
        let settings = viewModel.startPageSettings
        return settings.quickActionOrder.filter { settings.isQuickActionVisible($0) }
    }

    /// Inner content width for the landscape greeting card (before horizontal padding).
    private var startPageLandscapeGreetingCardMaxWidth: CGFloat { 280 }
    private var startPageLandscapeGreetingHorizontalPadding: CGFloat { 14 }

    /// Total width of the landscape greeting glass card (content + horizontal padding on each side).
    private var startPageLandscapeGreetingCardOuterWidth: CGFloat {
        startPageLandscapeGreetingCardMaxWidth + startPageLandscapeGreetingHorizontalPadding * 2
    }

    private enum StartPageQuickActionMetrics {
        static let rowContentHeight: CGFloat = 38
        static let chromePaddingHorizontal: CGFloat = 5
        static let chromePaddingVertical: CGFloat = 3
        /// Separator height between slots (centered in the row, shorter than full bar height).
        static let dividerHeight: CGFloat = 24
        /// Below this per-slot width (after dividers), labels hide and only icons show — single row, fixed height.
        static let minSlotWidthForCaption: CGFloat = 52
        static var totalRowHeight: CGFloat { rowContentHeight + chromePaddingVertical * 2 }
    }

    private var startPageQuickActions: some View {
        let settings = viewModel.startPageSettings
        let items = visibleQuickActionItems
        return Group {
            if settings.showQuickActions && !items.isEmpty {
                GeometryReader { geo in
                    let chromeH = StartPageQuickActionMetrics.chromePaddingHorizontal
                    let chromeV = StartPageQuickActionMetrics.chromePaddingVertical
                    let inner = max(geo.size.width - chromeH * 2, 1)
                    let n = items.count
                    let dividerCount = max(0, n - 1)
                    let slot = (inner - CGFloat(dividerCount)) / CGFloat(max(n, 1))
                    let showIconsOnly = slot < StartPageQuickActionMetrics.minSlotWidthForCaption

                    HStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(width: 1, height: StartPageQuickActionMetrics.dividerHeight)
                            }
                            startPageQuickActionCell(item: item, showIconsOnly: showIconsOnly)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, chromeH)
                    .padding(.vertical, chromeV)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: StartPageQuickActionMetrics.totalRowHeight)
            }
        }
    }

    private func startPageQuickActionCell(item: QuickActionItem, showIconsOnly: Bool) -> some View {
        Button {
            performStartPageQuickAction(item)
        } label: {
            Group {
                if showIconsOnly {
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(item.label)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .foregroundStyle(.secondary)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func performStartPageQuickAction(_ item: QuickActionItem) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        switch item {
        case .search:
            isAddressBarFocused = true
        case .tabOverview:
            withAnimation(.spring(duration: 0.45, bounce: 0.12)) {
                showTabOverview = true
            }
        case .bookmarks:
            selectedCollectionTab = .bookmarks
            showBookmarks = true
        case .history:
            selectedCollectionTab = .history
            showBookmarks = true
        case .favorites:
            selectedCollectionTab = .favorites
            showBookmarks = true
        case .settings:
            showSettings = true
        }
    }

    private var isCompactStartPage: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact && verticalSizeClass == .regular
        #else
        return false
        #endif
    }

    private var startPageTopPadding: CGFloat {
        if showStartPageOverlay && addressBarOnTop {
            return 12
        }
        #if os(iOS)
        if horizontalSizeClass == .regular || verticalSizeClass == .compact {
            return 30
        }
        return 70
        #else
        return 40
        #endif
    }

    private var favoritesColumnCount: Int {
        #if os(macOS)
        return 8
        #else
        return 4
        #endif
    }

    private func bookmarkQuickLink(_ bookmark: Bookmark) -> some View {
        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            viewModel.selectedTab?.load(bookmark.url)
            dismissStartPageOverlay()
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.primary.opacity(0.04))
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))

                    Text(siteLetter(for: bookmark.url))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .shadow(color: .black.opacity(0.06), radius: 10, y: 5)

                Text(bookmark.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 66)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .contextMenu {
            startPageGridContextMenu(for: bookmark.url)
        }
    }
    private func quickLink(_ name: String, url: String) -> some View {
        Button {
            if let url = URL(string: url) {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                viewModel.selectedTab?.load(url)
                dismissStartPageOverlay()
            }
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.primary.opacity(0.04))
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))

                    let initial = String(name.prefix(1)).uppercased()
                    Text(initial)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .shadow(color: .black.opacity(0.06), radius: 10, y: 5)

                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 66)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .contextMenu {
            if let parsed = URL(string: url) {
                startPageGridContextMenu(for: parsed)
            }
        }
    }

    // MARK: - Tab Overview

    private var tabOverview: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    let minWidth: CGFloat = {
                        #if os(iOS)
                        if horizontalSizeClass == .regular { return 200 }
                        if verticalSizeClass == .compact { return 180 }
                        #endif
                        return 160
                    }()
                    let columns = [GridItem(.adaptive(minimum: minWidth, maximum: 320), spacing: 20)]

                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(viewModel.tabs) { tab in
                            tabCard(for: tab)
                                .id(tab.id)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                                .contentShape(Rectangle())
                                .draggable(tab.id.uuidString) {
                                    RoundedRectangle(cornerRadius: 22)
                                        .fill(.quaternary)
                                        .frame(width: 120, height: 160)
                                        .overlay(
                                            Text(tab.title)
                                                .font(.system(size: 10))
                                                .lineLimit(1)
                                                .foregroundStyle(.secondary)
                                        )
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    guard let draggedIDString = items.first,
                                          let draggedID = UUID(uuidString: draggedIDString),
                                          let fromIndex = viewModel.tabs.firstIndex(where: { $0.id == draggedID }),
                                          let toIndex = viewModel.tabs.firstIndex(where: { $0.id == tab.id }),
                                          fromIndex != toIndex else { return false }
                                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                                        viewModel.tabs.move(
                                            fromOffsets: IndexSet(integer: fromIndex),
                                            toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
                                        )
                                    }
                                    return true
                                }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 110)
                }
                .onAppear {
                    if let selectedID = viewModel.selectedTabID {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }

            overviewBottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            (viewModel.isPrivate ? Color.purple.opacity(0.06) : Color.clear)
                .background(.ultraThickMaterial)
                .ignoresSafeArea()
        )
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.tabs.count)
        .sensoryFeedback(.selection, trigger: viewModel.activeGroup)
    }

    private var overviewBottomBar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                    viewModel.addNewTab()
                    showTabOverview = false
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .clipShape(Circle())

            Spacer()

            HStack(spacing: 0) {
                ForEach(TabGroup.allCases, id: \.self) { group in
                    Button {
                        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                            viewModel.switchGroup(group)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: group.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(groupLabel(for: group))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(minWidth: 90)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        viewModel.activeGroup == group ? .regular : .identity,
                        in: .capsule
                    )
                    .foregroundStyle(
                        viewModel.activeGroup == group
                            ? (group == .privateMode ? Color.purple : Color.primary)
                            : Color.secondary
                    )
                }
            }
            .padding(4)
            .glassEffect(.regular, in: .capsule)

            Spacer()

            Button {
                withAnimation(.spring(duration: 0.4, bounce: 0.12)) {
                    showTabOverview = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .clipShape(Circle())
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func groupLabel(for group: TabGroup) -> String {
        switch group {
        case .normal:
            let count = viewModel.normalTabs.count
            return "\(count) Tab\(count == 1 ? "" : "s")"
        case .privateMode:
            return "Private"
        }
    }

    private func tabCard(for tab: BrowserTab) -> some View {
        let isSelected = tab.id == viewModel.selectedTabID

        return Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.12)) {
                viewModel.selectTab(tab.id)
                showTabOverview = false
            }
        } label: {
            VStack(spacing: verticalSizeClass == .compact ? 6 : 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.quaternary.opacity(0.1))

                    if let image = tab.snapshotSwiftUIImage {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: tab.isPrivate ? "eye.slash.fill" : (tab.currentURL != nil ? "doc.richtext" : "globe"))
                                .font(.system(size: 32, weight: .ultraLight))
                                .foregroundStyle(tab.isPrivate ? Color.purple.opacity(0.5) : Color.secondary.opacity(0.4))
                            if tab.currentURL == nil {
                                Text(tab.isPrivate ? "New Private Tab" : "New Tab")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(tab.isPrivate ? Color.purple.opacity(0.4) : Color.secondary.opacity(0.35))
                            }
                        }
                    }
                }
                .frame(height: verticalSizeClass == .compact ? 140 : 240)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.clear,
                            lineWidth: isSelected ? 2.5 : 0
                        )
                )
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                            viewModel.closeTab(tab.id)
                            if viewModel.tabs.isEmpty {
                                showTabOverview = false
                            }
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .glassEffect(.regular, in: .circle)
                            .padding(4)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }

                HStack(spacing: 5) {
                    if tab.currentURL != nil {
                        favicon(for: tab, size: 13)
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 13, height: 13)
                    }

                    Text(tab.title)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .glassEffect(.regular, in: .capsule)
            }
            .padding(2)
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .contextMenu {
            if let url = tab.currentURL {
                Button {
                    #if os(iOS)
                    UIPasteboard.general.url = url
                    #elseif os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    #endif
                } label: {
                    Label("Copy Link", systemImage: "doc.on.doc")
                }

                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Divider()
            }

            if viewModel.tabs.count > 1 {
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                        viewModel.closeOtherTabs(tab.id)
                    }
                } label: {
                    Label("Close Other Tabs", systemImage: "xmark.square")
                }
            }

            Button(role: .destructive) {
                withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                    viewModel.closeTab(tab.id)
                    if viewModel.tabs.isEmpty {
                        showTabOverview = false
                    }
                }
            } label: {
                Label("Close Tab", systemImage: "trash")
            }
        }
    }

    // MARK: - Bottom Toolbar

    #if os(iOS)
    private var bottomToolbar: some View {
        HStack(spacing: 20) {
            toolbarButton(icon: "chevron.left", disabled: !(viewModel.selectedTab?.canGoBack ?? false)) {
                viewModel.selectedTab?.goBack()
            }

            toolbarButton(icon: "chevron.right", disabled: !(viewModel.selectedTab?.canGoForward ?? false)) {
                viewModel.selectedTab?.goForward()
            }

            if let url = viewModel.selectedTab?.currentURL {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 36, height: 36)
                }
            } else {
                toolbarButton(icon: "square.and.arrow.up", disabled: true) {}
            }

            Menu {
                moreMenuItems
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 36, height: 36)
            }

            Button {
                viewModel.snapshotAllTabs()
                withAnimation(.spring(duration: 0.45, bounce: 0.12)) {
                    showTabOverview = true
                }
            } label: {
                Image(systemName: "square.on.square")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 36, height: 36)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .scaleEffect(isToolbarExpanded ? 1.0 : 0.75, anchor: .bottom)
        .offset(y: isToolbarExpanded ? 0 : 50)
        .opacity(isToolbarExpanded ? 1.0 : 0.0)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .padding(.bottom, 0)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: isToolbarExpanded)
    }

    private func toolbarButton(icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 36, height: 36)
        }
        .disabled(disabled)
    }
    #endif

    // MARK: - History Sheet

    @ViewBuilder
    private var historyContent: some View {
        let sortedEntries = viewModel.historyStore.entries.sorted { $0.dateVisited > $1.dateVisited }
        let filteredEntries: [HistoryEntry] = {
            let q = collectionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return sortedEntries }
            return sortedEntries.filter {
                $0.title.localizedCaseInsensitiveContains(q) ||
                ($0.url.host?.localizedCaseInsensitiveContains(q) ?? false) ||
                $0.url.absoluteString.localizedCaseInsensitiveContains(q)
            }
        }()

        let groupedFiltered: [(String, [HistoryEntry])] = {
            let calendar = Calendar.current
            var groups: [String: [HistoryEntry]] = [:]
            var order: [String] = []

            let formatter: DateFormatter = {
                let f = DateFormatter()
                f.dateFormat = "EEEE, MMMM d"
                return f
            }()

            for entry in filteredEntries {
                let key: String
                if calendar.isDateInToday(entry.dateVisited) {
                    key = "Today"
                } else if calendar.isDateInYesterday(entry.dateVisited) {
                    key = "Yesterday"
                } else {
                    key = formatter.string(from: entry.dateVisited)
                }

                if groups[key] == nil { order.append(key) }
                groups[key, default: []].append(entry)
            }

            return order.map { ($0, groups[$0] ?? []) }.filter { !$0.1.isEmpty }
        }()

        List {
            if viewModel.historyStore.entries.isEmpty {
                Section {
                    Text("No History")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            } else if filteredEntries.isEmpty {
                Section {
                    Text("No Results Found")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            } else {
                ForEach(groupedFiltered, id: \.0) { group, entries in
                    Section(group) {
                        ForEach(entries) { entry in
                            Button {
                                viewModel.selectedTab?.load(entry.url)
                                showBookmarks = false
                            } label: {
                                HStack(spacing: 12) {
                                    let letter = siteLetter(for: entry.url)
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 9)
                                            .fill(Color.accentColor.opacity(0.12))
                                            .frame(width: 30, height: 30)
                                        Text(letter)
                                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.title.isEmpty ? (entry.url.host ?? "Website") : entry.title)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        
                                        HStack(spacing: 4) {
                                            Text(entry.url.host ?? entry.url.absoluteString)
                                            Text("•")
                                            Text(entry.dateVisited, style: .time)
                                        }
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    viewModel.addNewTab(url: entry.url)
                                    showBookmarks = false
                                } label: {
                                    Label("Open in New Tab", systemImage: "plus.square.on.square")
                                }

                                Button {
                                    copyURLToClipboard(entry.url)
                                } label: {
                                    Label("Copy Link", systemImage: "doc.on.doc")
                                }

                                ShareLink(item: entry.url) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    viewModel.historyStore.removeEntry(entry.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    viewModel.historyStore.removeEntry(entry.id)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Bookmarks Sheet

    private var collectionSheet: some View {
        TabView(selection: $selectedCollectionTab) {
            NavigationStack {
                bookmarksContent
                    .navigationTitle("Bookmarks")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showBookmarks = false }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            EditButton()
                        }
                    }
            }
            .tabItem {
                Label("Bookmarks", systemImage: "star.fill")
            }
            .tag(CollectionTab.bookmarks)

            NavigationStack {
                favoritesContent
                    .navigationTitle("Favorites")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showBookmarks = false }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            EditButton()
                        }
                    }
            }
            .tabItem {
                Label("Favorites", systemImage: "heart.fill")
            }
            .tag(CollectionTab.favorites)

            NavigationStack {
                historyContent
                    .navigationTitle("History")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showBookmarks = false }
                        }
                        ToolbarItem(placement: .destructiveAction) {
                            if !viewModel.historyStore.entries.isEmpty {
                                Button("Clear", role: .destructive) {
                                    viewModel.historyStore.clearHistory()
                                }
                            }
                        }
                    }
            }
            .tabItem {
                Label("History", systemImage: "clock.fill")
            }
            .tag(CollectionTab.history)
        }
        .searchable(text: $collectionSearchText, placement: .navigationBarDrawer(displayMode: .always))
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        #endif
    }

    @ViewBuilder
    private var bookmarksContent: some View {
        let filteredBookmarks: [Bookmark] = {
            let q = collectionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return viewModel.bookmarkStore.bookmarks }
            return viewModel.bookmarkStore.bookmarks.filter {
                $0.title.localizedCaseInsensitiveContains(q) ||
                ($0.url.host?.localizedCaseInsensitiveContains(q) ?? false) ||
                $0.url.absoluteString.localizedCaseInsensitiveContains(q)
            }
        }()

        List {
            Section {
                if filteredBookmarks.isEmpty && !collectionSearchText.isEmpty {
                    Text("No Results Found")
                        .foregroundStyle(.secondary)
                        .italic()
                } else if viewModel.bookmarkStore.bookmarks.isEmpty {
                    Text("No Bookmarks")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(filteredBookmarks) { bookmark in
                        Button {
                            viewModel.selectedTab?.load(bookmark.url)
                            showBookmarks = false
                        } label: {
                            HStack(spacing: 12) {
                                let letter = siteLetter(for: bookmark.url)
                                ZStack {
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(Color.accentColor.opacity(0.12))
                                        .frame(width: 30, height: 30)
                                    Text(letter)
                                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bookmark.title)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    
                                    Text(bookmark.url.host ?? bookmark.url.absoluteString)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                viewModel.addNewTab(url: bookmark.url)
                                showBookmarks = false
                            } label: {
                                Label("Open in New Tab", systemImage: "plus.square.on.square")
                            }

                            Button {
                                copyURLToClipboard(bookmark.url)
                            } label: {
                                Label("Copy Link", systemImage: "doc.on.doc")
                            }

                            ShareLink(item: bookmark.url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }

                            Divider()

                            Button(role: .destructive) {
                                viewModel.bookmarkStore.removeBookmark(id: bookmark.id)
                            } label: {
                                Label("Delete Bookmark", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let id = filteredBookmarks[index].id
                            viewModel.bookmarkStore.removeBookmark(id: id)
                        }
                    }
                    .onMove { from, to in
                        viewModel.bookmarkStore.moveBookmark(from: from, to: to)
                    }
                }
            } header: {
                Text("Your Bookmarks")
            } footer: {
                Text("Drag to reorder bookmarks.")
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var favoritesContent: some View {
        let filteredFavorites: [Favorite] = {
            let q = collectionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return viewModel.favoriteStore.favorites }
            return viewModel.favoriteStore.favorites.filter {
                $0.title.localizedCaseInsensitiveContains(q) ||
                ($0.url.host?.localizedCaseInsensitiveContains(q) ?? false) ||
                $0.url.absoluteString.localizedCaseInsensitiveContains(q)
            }
        }()

        List {
            Section {
                if filteredFavorites.isEmpty && !collectionSearchText.isEmpty {
                    Text("No Results Found")
                        .foregroundStyle(.secondary)
                        .italic()
                } else if viewModel.favoriteStore.favorites.isEmpty {
                    Text("No Favorites")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(filteredFavorites) { favorite in
                        Button {
                            viewModel.selectedTab?.load(favorite.url)
                            showBookmarks = false
                        } label: {
                            HStack(spacing: 12) {
                                let letter = String(favorite.title.prefix(1)).uppercased()
                                ZStack {
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(Color.accentColor.opacity(0.12))
                                        .frame(width: 30, height: 30)
                                    Text(letter)
                                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                                        .foregroundStyle(Color.accentColor)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(favorite.title)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(favorite.url.host ?? favorite.url.absoluteString)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                viewModel.addNewTab(url: favorite.url)
                                showBookmarks = false
                            } label: {
                                Label("Open in New Tab", systemImage: "plus.square.on.square")
                            }

                            Button {
                                copyURLToClipboard(favorite.url)
                            } label: {
                                Label("Copy Link", systemImage: "doc.on.doc")
                            }

                            ShareLink(item: favorite.url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }

                            Divider()

                            Button(role: .destructive) {
                                viewModel.favoriteStore.removeFavorite(id: favorite.id)
                            } label: {
                                Label("Remove Favorite", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let id = filteredFavorites[index].id
                            viewModel.favoriteStore.removeFavorite(id: id)
                        }
                    }
                    .onMove { from, to in
                        viewModel.favoriteStore.moveFavorite(from: from, to: to)
                    }
                }
            } header: {
                Text("Your Favorites")
            } footer: {
                Text("Drag to reorder favorite shortcuts on your Start Page.")
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Settings Sheet

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Picker(selection: $viewModel.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    } label: {
                        settingsRow(
                            title: "Theme",
                            systemImage: "paintpalette",
                            color: .blue
                        )
                    }
                    .pickerStyle(.navigationLink)

                    Picker(selection: $viewModel.searchEngine) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(engine.label).tag(engine)
                        }
                    } label: {
                        settingsRow(
                            title: "Search Engine",
                            systemImage: "magnifyingglass",
                            color: .blue
                        )
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Interface") {
                    Toggle(isOn: $viewModel.showTabStrip) {
                        settingsRow(
                            title: "Show Tab Bar",
                            systemImage: "menubar.dock.rectangle",
                            color: .blue
                        )
                    }

                    Button {
                        showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showCustomizeStartPage = true
                        }
                    } label: {
                        settingsRow(
                            title: "Customize Start Page",
                            systemImage: "slider.horizontal.3",
                            color: .purple
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showOnboarding = true
                        }
                    } label: {
                        settingsRow(
                            title: "View Onboarding",
                            systemImage: "wand.and.stars",
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)
                }


                Section("Data") {
                    Button(role: .destructive) {
                        showClearHistoryConfirmation = true
                    } label: {
                        settingsRow(
                            title: "Clear History",
                            subtitle: viewModel.historyStore.entries.isEmpty ? nil : "\(viewModel.historyStore.entries.count) visits",
                            systemImage: "clock.arrow.circlepath",
                            color: .red
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.historyStore.entries.isEmpty)
                    .alert("Clear All History?", isPresented: $showClearHistoryConfirmation) {
                        Button("Clear", role: .destructive) {
                            viewModel.historyStore.clearHistory()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently remove all \(viewModel.historyStore.entries.count) history entries. This action cannot be undone.")
                    }

                    Button(role: .destructive) {
                        showCloseAllTabsConfirmation = true
                    } label: {
                        settingsRow(
                            title: "Close All Tabs",
                            subtitle: viewModel.tabs.count > 1 ? "\(viewModel.tabs.count) tabs" : nil,
                            systemImage: "xmark.square",
                            color: .red
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.tabs.count <= 1 && viewModel.selectedTab?.currentURL == nil)
                    .alert("Close All Tabs?", isPresented: $showCloseAllTabsConfirmation) {
                        Button("Close All", role: .destructive) {
                            viewModel.closeAllTabs()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will close all \(viewModel.tabs.count) open tabs.")
                    }
                }

                Section {
                    settingsRow(
                        title: "Version",
                        subtitle: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                        systemImage: "info.circle",
                        color: .secondary
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettings = false }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }

    // MARK: - Onboarding Screen

    private var onboardingScreen: some View {
        ZStack {
            let (c1, c2) = startPageGradientColors
            
            // Full background without conditional clear checks for consistency
            ZStack {
                LinearGradient(
                    colors: startPageAmbientBaseGradient,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(0.35)
                
                RadialGradient(
                    colors: [c1.opacity(0.38), c1.opacity(0.15), .clear],
                    center: .topLeading,
                    startRadius: 40,
                    endRadius: 560
                )
                
                RadialGradient(
                    colors: [c2.opacity(0.34), c2.opacity(0.14), .clear],
                    center: .bottomTrailing,
                    startRadius: 30,
                    endRadius: 520
                )
            }
            .ignoresSafeArea()
            .background(
                Rectangle() // Extra fallback
                    .fill(.background)
                    .ignoresSafeArea()
            )

            TabView(selection: $onboardingStep) {
                onboardingWelcomePage
                    .tag(0)
                
                onboardingHeroPage(
                    icon: "bolt.circle.fill",
                    gradient: [.orange, .yellow],
                    title: "Lightning Fast",
                    subtitle: "Open pages quickly with a lightweight browsing engine tuned for responsiveness.",
                    highlights: [("speedometer", "Fast Load"), ("waveform.path.ecg", "Smooth")]
                )
                .tag(1)
                
                onboardingHeroPage(
                    icon: "slider.horizontal.3",
                    gradient: [.purple, .pink],
                    title: "Built Around You",
                    subtitle: "Customize your start page, theme, and shortcuts to match the way you browse.",
                    highlights: [("paintbrush.pointed.fill", "Themes"), ("square.grid.2x2.fill", "Shortcuts")]
                )
                .tag(2)
                
                onboardingHeroPage(
                    icon: "square.stack.3d.up.fill",
                    gradient: [.blue, .cyan],
                    title: "Intelligent Tabs",
                    subtitle: "Keep everything organized with smarter tab management and a clear workspace overview.",
                    highlights: [("rectangle.stack.fill", "Groups"), ("sparkles", "Smart View")]
                )
                .tag(3)
                
                onboardingHeroPage(
                    icon: "lock.shield.fill",
                    gradient: [.green, .teal],
                    title: "Private by Default",
                    subtitle: "Stay in control with secure browsing, private sessions, and stronger data separation.",
                    highlights: [("eye.slash.fill", "Private"), ("checkmark.shield.fill", "Secure")]
                )
                .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.spring(duration: 0.5, bounce: 0.15), value: onboardingStep)

            // Bottom Layout: Dots & Button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        triggerOnboardingHaptic(style: .light)
                        hasSeenOnboarding = true
                        showOnboarding = false
                        onboardingStep = 0
                    } label: {
                        Text("Skip")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .opacity(onboardingStep < 4 ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: onboardingStep)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                Spacer()
                VStack(spacing: 36) {
                    // Custom Pagination Dots
                    HStack(spacing: 10) {
                        ForEach(0..<5) { i in
                            Capsule()
                                .fill(onboardingStep == i ? Color.primary : Color.primary.opacity(0.15))
                                .frame(width: onboardingStep == i ? 36 : 8, height: 8)
                                .animation(.spring(duration: 0.4, bounce: 0.4), value: onboardingStep)
                        }
                    }

                    Button {
                        if onboardingStep < 4 {
                            triggerOnboardingHaptic(style: .light)
                            withAnimation(.spring(duration: 0.5, bounce: 0.15)) {
                                onboardingStep += 1
                            }
                        } else {
                            triggerOnboardingCompletionHaptic()
                            hasSeenOnboarding = true
                            showOnboarding = false
                            onboardingStep = 0 // Reset for next time
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text(onboardingStep < 4 ? "Continue" : "Get Started")
                                .font(.system(size: 17, weight: .bold))
                            Image(systemName: onboardingStep < 4 ? "arrow.right" : "checkmark")
                                .font(.system(size: 14, weight: .bold))
                        }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.accentColor.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 10, y: 5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .animation(.spring(duration: 0.4, bounce: 0.2), value: onboardingStep)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            onboardingStep = 0
        }
    }

    private var onboardingWelcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.accentColor.opacity(0.32), .purple.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 220, height: 220)
                    .blur(radius: 30)

                Image("OnboardingLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 156, height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .shadow(color: Color.cyan.opacity(0.45), radius: 30, y: 0)
                    .shadow(color: Color.blue.opacity(0.35), radius: 44, y: 0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.24), radius: 20, y: 12)
            }
            .padding(.bottom, 8)
            
            VStack(spacing: 12) {
                Text("Welcome to")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("X Browser")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .tracking(0.6)
                Text("Fast, focused, and private browsing.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)

            HStack(spacing: 10) {
                onboardingContentChip(icon: "bolt.fill", label: "Fast")
                onboardingContentChip(icon: "slider.horizontal.3", label: "Custom")
                onboardingContentChip(icon: "lock.fill", label: "Private")
            }
            
            Spacer()
            Spacer()
        }
    }

    private func onboardingHeroPage(icon: String, gradient: [Color], title: String, subtitle: String, highlights: [(String, String)]) -> some View {
        VStack(spacing: 36) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [gradient.first?.opacity(0.35) ?? .clear, gradient.last?.opacity(0.2) ?? .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 150, height: 150)
                    .blur(radius: 24)
                
                Image(systemName: icon)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 122, height: 122)
                    .background(
                        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: (gradient.last ?? .black).opacity(0.4), radius: 25, y: 15)
                    .symbolRenderingMode(.hierarchical)
            }
            
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                
                Text(subtitle)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 6)

                HStack(spacing: 10) {
                    ForEach(Array(highlights.enumerated()), id: \.offset) { _, item in
                        onboardingContentChip(icon: item.0, label: item.1)
                    }
                }
                .padding(.top, 2)
            }
            .padding(30)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func onboardingContentChip(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.08), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func triggerOnboardingHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }

    private func triggerOnboardingCompletionHaptic() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    private func handleHomeScreenQuickAction(_ action: HomeScreenQuickAction) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        switch action {
        case .newTab:
            viewModel.addNewTab()
            showTabOverview = false
            showStartPageOverlay = false
        case .bookmarks:
            selectedCollectionTab = .bookmarks
            showHistory = false
            showBookmarks = true
        case .history:
            selectedCollectionTab = .history
            showBookmarks = false
            showHistory = true
        case .settings:
            showSettings = true
        }
    }

    // MARK: - Helpers

    private func settingsRow(title: String, subtitle: String? = nil, systemImage: String, color: Color = .accentColor) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7))

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dismissStartPageOverlay() {
        isAddressBarFocused = false
        withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
            showStartPageOverlay = false
        }
    }

    private func syncAddressText() {
        guard let tab = viewModel.selectedTab else {
            addressText = ""
            return
        }
        if let host = tab.currentURL?.host {
            addressText = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        } else {
            addressText = ""
        }
    }

    private func toggleFindBar() {
        if showFindBar {
            dismissFindBar()
        } else {
            showFindBar = true
            isFindBarFocused = true
        }
    }

    private func dismissFindBar() {
        showFindBar = false
        findText = ""
        isFindBarFocused = false
        viewModel.selectedTab?.clearFind()
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<21: return "Good Evening"
        default: return "Good Night"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private var formattedDate: String {
        Self.dateFormatter.string(from: Date())
    }

    private var timeOfDayColors: (Color, Color) {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<8: return (.yellow, .orange)
        case 8..<12: return (.mint, .cyan)
        case 12..<17: return (.blue, .mint)
        case 17..<21: return (.orange, .pink)
        default: return (.indigo, .purple)
        }
    }

    private var startPageGradientColors: (Color, Color) {
        if showStartPageOverlay && addressBarOnTop {
            return (.primary, .primary.opacity(0.8))
        }
        switch viewModel.startPageSettings.gradientPreset {
        case .monochrome:
            return (.gray, .black)
        case .dynamic:
            return timeOfDayColors
        case .ocean:
            return (.cyan, .blue)
        case .sunset:
            return (.yellow, .red)
        case .aurora:
            return (.mint, .purple)
        case .midnight:
            return (.indigo, .purple)
        case .dawn:
            return (.yellow, .orange)
        case .tropical:
            return (.mint, .teal)
        case .candy:
            return (.pink, .purple)
        case .neon:
            return (.green, .cyan)
        }
    }

    @ViewBuilder
    private func startPageGridContextMenu(for url: URL) -> some View {
        Button {
            openStartPageURL(url)
        } label: {
            Label("Open", systemImage: "arrow.up.forward")
        }

        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            viewModel.addNewTab(url: url)
            dismissStartPageOverlay()
        } label: {
            Label("Open in New Tab", systemImage: "plus.square.on.square")
        }

        Divider()

        Button {
            copyURLToClipboard(url)
        } label: {
            Label("Copy Link", systemImage: "doc.on.doc")
        }

        ShareLink(item: url) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    private func openStartPageURL(_ url: URL) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        viewModel.selectedTab?.load(url)
        dismissStartPageOverlay()
    }

    private func copyURLToClipboard(_ url: URL) {
        #if os(iOS) || os(visionOS)
        UIPasteboard.general.string = url.absoluteString
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #endif
    }

    private func favicon(for tab: BrowserTab, size: CGFloat) -> some View {
        Circle()
            .fill(faviconColor(for: tab).gradient)
            .frame(width: size, height: size)
            .overlay(
                Text(faviconLetter(for: tab))
                    .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            )
    }

    private static let colorPalette: [Color] = [
        .blue, .red, .green, .orange, .purple,
        .pink, .teal, .indigo, .cyan, .mint
    ]

    private func faviconColor(for tab: BrowserTab) -> Color {
        guard let host = tab.currentURL?.host else { return .gray }
        return Self.colorForHost(host)
    }

    private func faviconLetter(for tab: BrowserTab) -> String {
        guard let host = tab.currentURL?.host else { return "" }
        return Self.letterForHost(host)
    }

    private func siteColor(for url: URL) -> Color {
        guard let host = url.host else { return .gray }
        return Self.colorForHost(host)
    }

    private func siteLetter(for url: URL) -> String {
        guard let host = url.host else { return "" }
        return Self.letterForHost(host)
    }

    private static func colorForHost(_ host: String) -> Color {
        let hash = host.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colorPalette[hash % colorPalette.count]
    }

    private static func letterForHost(_ host: String) -> String {
        let cleaned = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return String(cleaned.prefix(1)).uppercased()
    }
}

#Preview {
    ContentView()
}
