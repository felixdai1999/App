import SwiftUI

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

struct ContentView: View {
    private enum SwipePreviewDirection: Equatable {
        case previous
        case next
    }

    @State private var viewModel = BrowserViewModel()
    @State private var addressText = ""
    @State private var addressBarOffset: CGFloat = 0
    @State private var addressBarWidth: CGFloat = 0
    @FocusState private var isAddressBarFocused: Bool
    @State private var showTabOverview = false
    @State private var showFindBar = false
    @State private var findText = ""
    @FocusState private var isFindBarFocused: Bool
    @State private var showHistory = false
    @State private var showBookmarks = false
    @State private var showSettings = false
    @State private var historySearchText = ""
    @State private var bookmarkSearchText = ""
    @State private var bookmarkSortIsRecentFirst = true
    @State private var showCustomizeStartPage = false
    @State private var showStartPageOverlay = false
    @State private var bottomContainerWidth: CGFloat = 300
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var shouldShowTabStrip: Bool {
        #if os(iOS)
        let isEligibleClass = horizontalSizeClass == .regular || verticalSizeClass == .compact
        return isEligibleClass && isToolbarExpanded
        #else
        return true
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
                .scaleEffect(showTabOverview ? 0.92 : 1)
                .opacity(showTabOverview ? 0 : 1)
                .allowsHitTesting(!showTabOverview)

            if showTabOverview {
                tabOverview
                    .transition(.opacity)
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
                if viewModel.selectedTab?.currentURL != nil {
                    withAnimation(.spring(duration: 0.4, bounce: 0.08)) {
                        showStartPageOverlay = true
                    }
                }
            } else {
                withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
                    showStartPageOverlay = false
                }
                syncAddressText()
            }
        }
        .overlay { keyboardShortcuts }
        .sensoryFeedback(.selection, trigger: viewModel.selectedTabID)
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.tabs.count)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.7), trigger: viewModel.bookmarkStore.bookmarks.count)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: showFindBar)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.6), trigger: showTabOverview)
        .sheet(isPresented: $showHistory) {
            historySheet
        }
        .sheet(isPresented: $showBookmarks) {
            bookmarksSheet
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
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
                showHistory = true
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
            .clipShape(Capsule())
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 10)
            .onChange(of: viewModel.selectedTabID) { _, newID in
                if let id = newID {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
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
                if isSelected {
                    // Balancing space for the close button
                    Color.clear.frame(width: 14, height: 14)
                }

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
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(width: tabWidth)
            .contentShape(Rectangle())
            .background(isSelected ? Color.primary.opacity(0.08) : Color.clear, in: .capsule)
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
                                    .foregroundStyle(.primary)
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
                            viewModel.selectedTab?.loadRequest(addressText)
                            isAddressBarFocused = false
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
                        .foregroundStyle(.primary)
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
                                }
                                return
                            }
                        }

                        let projectedWidth = value.predictedEndTranslation.width
                        let translation = value.translation.width
                        let transitionWidth = max(addressBarWidth, 320)
                        let triggerDistance = max(addressBarWidth * 0.18, 56)
                        let canSwipeForward = canCreateNewTabBySwipe || ((selectedTabIndex ?? -1) < (viewModel.tabs.count - 1))
    
                        if translation > triggerDistance || projectedWidth > triggerDistance * 1.35 {
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
                        } else if canSwipeForward && (translation < -triggerDistance || projectedWidth < -triggerDistance * 1.35) {
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

            Divider()
        }

        Button { showBookmarks = true } label: {
            Label("Bookmarks", systemImage: "book")
        }

        Button { showHistory = true } label: {
            Label("History", systemImage: "clock.arrow.circlepath")
        }

        Button { showSettings = true } label: {
            Label("Settings", systemImage: "gearshape")
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
                    let offset = (difference * geo.size.width) + addressBarOffset
                    let distance = min(abs(offset) / max(geo.size.width, 1), CGFloat(1.1))
                    let parallaxOffset = difference == 0 ? addressBarOffset : (addressBarOffset * 0.08)
                    
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
                        .offset(x: (difference * geo.size.width) + parallaxOffset)
                        .opacity(Double(CGFloat(1) - (distance * CGFloat(0.12))))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()

            if showStartPageOverlay {
                Color(uiColor: .systemBackground)
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

    // MARK: - Start Page

    private var startPage: some View {
        let settings = viewModel.startPageSettings
        return ZStack {
            startPageBackground

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: startPageTopPadding)

                    if isCompactStartPage {
                        // Portrait iPhone: centered greeting + actions below
                        if settings.showGreeting {
                            VStack(spacing: 4) {
                                Text(greeting)
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(
                                        .linearGradient(
                                            colors: [timeOfDayColors.0, timeOfDayColors.1],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )

                                Text(formattedDate)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.tertiary)
                                    .textCase(.uppercase)
                                    .tracking(1.2)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }

                        startPageQuickActions
                            .padding(.top, settings.showGreeting ? 18 : 8)
                            .padding(.horizontal, 24)
                    } else {
                        // Landscape / iPad / macOS: left-aligned, same row
                        HStack(alignment: .firstTextBaseline) {
                            if settings.showGreeting {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(greeting)
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundStyle(
                                            .linearGradient(
                                                colors: [timeOfDayColors.0, timeOfDayColors.1],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )

                                    Text(formattedDate)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                        .textCase(.uppercase)
                                        .tracking(1.2)
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }

                            Spacer()

                            startPageQuickActions
                        }
                        .padding(.horizontal, 24)
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
                    .padding(.top, 36)

                    Spacer(minLength: 50)
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .animation(.spring(duration: 0.4, bounce: 0.15), value: settings.sectionOrder.map(\.rawValue))
                .animation(.spring(duration: 0.35, bounce: 0.1), value: settings.showGreeting)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: viewModel.bottomBarHeight)
            }
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: viewModel.topBarHeight)
            }
        }
        .sheet(isPresented: $showCustomizeStartPage) {
            customizeStartPageSheet
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
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader("BOOKMARKS")

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: favoritesColumnCount),
                        spacing: 14
                    ) {
                        ForEach(viewModel.bookmarkStore.bookmarks.prefix(favoritesColumnCount * 2)) { bookmark in
                            bookmarkQuickLink(bookmark)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
            }
        case .favorites:
            if settings.isSectionVisible(section) {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader("FAVORITES")

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: favoritesColumnCount),
                        spacing: 14
                    ) {
                        quickLink("Apple", url: "https://www.apple.com", icon: "apple.logo", color: .gray)
                        quickLink("Google", url: "https://www.google.com", icon: "magnifyingglass", color: .blue)
                        quickLink("GitHub", url: "https://www.github.com", icon: "chevron.left.forwardslash.chevron.right", color: .purple)
                        quickLink("YouTube", url: "https://www.youtube.com", icon: "play.rectangle.fill", color: .red)
                        quickLink("Reddit", url: "https://www.reddit.com", icon: "bubble.left.and.bubble.right.fill", color: .orange)
                        quickLink("Wikipedia", url: "https://www.wikipedia.org", icon: "book.closed.fill", color: .indigo)
                        quickLink("Twitter", url: "https://www.x.com", icon: "at", color: .cyan)
                        quickLink("News", url: "https://news.ycombinator.com", icon: "newspaper.fill", color: .mint)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(.tertiary)
            .tracking(1.8)
            .padding(.horizontal, 4)
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
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("RECENTLY VISITED")
                .padding(.horizontal, 28)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentlyVisitedEntries) { entry in
                        let color = siteColor(for: entry.url)
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            viewModel.selectedTab?.load(entry.url)
                            dismissStartPageOverlay()
                        } label: {
                            VStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(color.opacity(0.12))
                                        .frame(width: 56, height: 56)

                                    Text(siteLetter(for: entry.url))
                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                                        .foregroundStyle(color)
                                }
                                .shadow(color: color.opacity(0.2), radius: 8, y: 4)

                                Text(hostLabel(for: entry.url))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 66)
                            }
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                .padding(.horizontal, 28)
            }
        }
        .padding(.top, 32)
    }

    private func hostLabel(for url: URL) -> String {
        guard let host = url.host else { return url.absoluteString }
        let cleaned = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return cleaned.components(separatedBy: ".").first?.capitalized ?? cleaned
    }

    private var startPageBackground: some View {
        let (c1, c2) = timeOfDayColors
        return ZStack {
            // Primary ambient glow — top left
            RadialGradient(
                colors: [c1.opacity(0.16), c1.opacity(0.04), .clear],
                center: .topLeading,
                startRadius: 40,
                endRadius: 550
            )

            // Secondary ambient glow — bottom right
            RadialGradient(
                colors: [c2.opacity(0.12), c2.opacity(0.03), .clear],
                center: .bottomTrailing,
                startRadius: 30,
                endRadius: 500
            )

            // Soft center blend
            RadialGradient(
                colors: [c1.opacity(0.025), c2.opacity(0.02), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 400
            )

            // Subtle top-center highlight for depth
            RadialGradient(
                colors: [.white.opacity(0.025), .clear],
                center: .top,
                startRadius: 10,
                endRadius: 300
            )
        }
        .ignoresSafeArea()
    }

    private var startPageQuickActions: some View {
        HStack(spacing: 8) {
            startPagePill("Search", icon: "magnifyingglass") {
                isAddressBarFocused = true
            }

            startPagePill("Bookmarks", icon: "star.fill") {
                showBookmarks = true
            }

            startPagePill("History", icon: "clock.fill") {
                showHistory = true
            }

            startPagePill("Settings", icon: "gearshape.fill") {
                showSettings = true
            }

            if viewModel.canReopenTab {
                startPagePill("Reopen", icon: "arrow.uturn.forward") {
                    withAnimation(.snappy(duration: 0.25)) {
                        viewModel.reopenLastClosedTab()
                    }
                }
            }
        }
    }

    private func startPagePill(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var isCompactStartPage: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact && verticalSizeClass == .regular
        #else
        return false
        #endif
    }

    private var startPageTopPadding: CGFloat {
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
        let color = siteColor(for: bookmark.url)
        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            viewModel.selectedTab?.load(bookmark.url)
            dismissStartPageOverlay()
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(color.opacity(0.12))
                        .frame(width: 56, height: 56)

                    Text(siteLetter(for: bookmark.url))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                }
                .shadow(color: color.opacity(0.2), radius: 8, y: 4)

                Text(bookmark.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 66)
            }
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func quickLink(_ name: String, url: String, icon: String, color: Color) -> some View {
        Button {
            if let url = URL(string: url) {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                viewModel.selectedTab?.load(url)
                dismissStartPageOverlay()
            }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(color.opacity(0.12))
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(color)
                }
                .shadow(color: color.opacity(0.2), radius: 8, y: 4)

                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 66)
            }
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Tab Overview

    private var tabOverview: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                let columns = [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ]

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.tabs) { tab in
                        tabCard(for: tab)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                            .draggable(tab.id.uuidString) {
                                RoundedRectangle(cornerRadius: 14)
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
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 80)
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
            VStack(spacing: 0) {
                ZStack {
                    Rectangle()
                        .fill(.quaternary.opacity(0.15))

                    if let image = tab.snapshotSwiftUIImage {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: tab.isPrivate ? "eye.slash.fill" : (tab.currentURL != nil ? "doc.richtext" : "globe"))
                                .font(.system(size: 30, weight: .ultraLight))
                                .foregroundStyle(tab.isPrivate ? Color.purple.opacity(0.5) : Color.secondary.opacity(0.5))
                            if tab.currentURL == nil {
                                Text(tab.isPrivate ? "New Private Tab" : "New Tab")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(tab.isPrivate ? Color.purple.opacity(0.4) : Color.secondary.opacity(0.4))
                            }
                        }
                    }
                }
                .frame(height: 250)
                .clipped()
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
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .glassEffect(.regular, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }

                HStack(spacing: 6) {
                    if tab.currentURL != nil {
                        favicon(for: tab, size: 14)
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                    }

                    Text(tab.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 14,
                    bottomTrailingRadius: 14, topTrailingRadius: 0
                ))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: isSelected ? 2.5 : 0
                    )
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 5)
        }
        .buttonStyle(PressableButtonStyle())
        .contextMenu {
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

    private var historySheet: some View {
        let sortedEntries = viewModel.historyStore.entries.sorted { $0.dateVisited > $1.dateVisited }
        let filteredEntries: [HistoryEntry] = {
            let q = historySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

        return NavigationStack {
            Group {
                if viewModel.historyStore.entries.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock",
                        description: Text("Pages you visit will appear here.")
                    )
                } else {
                    if filteredEntries.isEmpty {
                        ContentUnavailableView(
                            "No Results",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different search.")
                        )
                    } else {
                        List {
                            ForEach(groupedFiltered, id: \.0) { group, entries in
                                Section(group) {
                                    ForEach(entries) { entry in
                                        Button {
                                            viewModel.selectedTab?.load(entry.url)
                                            showHistory = false
                                        } label: {
                                            HStack(spacing: 12) {
                                                let color = siteColor(for: entry.url)
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 9)
                                                        .fill(color.opacity(0.12))
                                                        .frame(width: 30, height: 30)

                                                    Text(siteLetter(for: entry.url))
                                                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                                                        .foregroundStyle(color)
                                                }

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(entry.title)
                                                        .font(.system(size: 15, weight: .medium))
                                                        .foregroundStyle(.primary)
                                                        .lineLimit(1)

                                                    Text(entry.url.host ?? entry.url.absoluteString)
                                                        .font(.system(size: 12))
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }

                                                Spacer(minLength: 0)

                                                Text(entry.dateVisited, style: .time)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.tertiary)
                                            }
                                            .contentShape(Rectangle())
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button("Delete", role: .destructive) {
                                                viewModel.historyStore.removeEntry(entry.id)
                                            }
                                        }
                                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                            Button {
                                                UIPasteboard.general.string = entry.url.absoluteString
                                            } label: {
                                                Label("Copy", systemImage: "doc.on.doc")
                                            }
                                            .tint(.blue)
                                        }
                                        .contextMenu {
                                            Button {
                                                UIPasteboard.general.string = entry.url.absoluteString
                                            } label: {
                                                Label("Copy Link", systemImage: "link")
                                            }

                                            ShareLink(item: entry.url) {
                                                Label("Share…", systemImage: "square.and.arrow.up")
                                            }

                                            Button(role: .destructive) {
                                                viewModel.historyStore.removeEntry(entry.id)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle("History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $historySearchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showHistory = false }
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
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    // MARK: - Bookmarks Sheet

    private var bookmarksSheet: some View {
        let sortedBookmarks: [Bookmark] = {
            let bookmarks = viewModel.bookmarkStore.bookmarks
            if bookmarkSortIsRecentFirst {
                return bookmarks.sorted { $0.dateAdded > $1.dateAdded }
            } else {
                return bookmarks.sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            }
        }()

        let filteredBookmarks: [Bookmark] = {
            let q = bookmarkSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return sortedBookmarks }
            return sortedBookmarks.filter {
                $0.title.localizedCaseInsensitiveContains(q) ||
                ($0.url.host?.localizedCaseInsensitiveContains(q) ?? false) ||
                $0.url.absoluteString.localizedCaseInsensitiveContains(q)
            }
        }()

        return NavigationStack {
            Group {
                if viewModel.bookmarkStore.bookmarks.isEmpty {
                    ContentUnavailableView(
                        "No Bookmarks",
                        systemImage: "star",
                        description: Text("Tap the star in the address bar to bookmark a page.")
                    )
                } else {
                    if filteredBookmarks.isEmpty {
                        ContentUnavailableView(
                            "No Results",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different search.")
                        )
                    } else {
                        List {
                            Section {
                                ForEach(filteredBookmarks) { bookmark in
                                    Button {
                                        viewModel.selectedTab?.load(bookmark.url)
                                        showBookmarks = false
                                    } label: {
                                        HStack(spacing: 12) {
                                            let color = siteColor(for: bookmark.url)
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 9)
                                                    .fill(color.opacity(0.12))
                                                    .frame(width: 30, height: 30)

                                                Text(siteLetter(for: bookmark.url))
                                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                                    .foregroundStyle(color)
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

                                            Spacer(minLength: 0)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button("Delete", role: .destructive) {
                                            viewModel.bookmarkStore.removeBookmark(id: bookmark.id)
                                        }
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        Button {
                                            UIPasteboard.general.string = bookmark.url.absoluteString
                                        } label: {
                                            Label("Copy", systemImage: "doc.on.doc")
                                        }
                                        .tint(.blue)
                                    }
                                    .contextMenu {
                                        Button {
                                            UIPasteboard.general.string = bookmark.url.absoluteString
                                        } label: {
                                            Label("Copy Link", systemImage: "link")
                                        }

                                        ShareLink(item: bookmark.url) {
                                            Label("Share…", systemImage: "square.and.arrow.up")
                                        }

                                        Button(role: .destructive) {
                                            viewModel.bookmarkStore.removeBookmark(id: bookmark.id)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle("Bookmarks")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $bookmarkSearchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showBookmarks = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            bookmarkSortIsRecentFirst = true
                        } label: {
                            Label("Sort by Recently Added", systemImage: bookmarkSortIsRecentFirst ? "checkmark" : "")
                        }

                        Button {
                            bookmarkSortIsRecentFirst = false
                        } label: {
                            Label("Sort by Title", systemImage: bookmarkSortIsRecentFirst ? "" : "checkmark")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort")
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    // MARK: - Settings Sheet

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section("Start Page") {
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
                }

                Section("Data") {
                    Button(role: .destructive) {
                        viewModel.historyStore.clearHistory()
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

                    Button(role: .destructive) {
                        viewModel.closeAllTabs()
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
        case 5..<8:  return (.orange, .pink)
        case 8..<12: return (.cyan, .blue)
        case 12..<17: return (.blue, .teal)
        case 17..<21: return (.purple, .orange)
        default: return (.indigo, .purple)
        }
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
