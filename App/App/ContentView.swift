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
                addressText = viewModel.selectedTab?.currentURL?.absoluteString ?? ""
            } else {
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

    private var browserView: some View {
        ZStack(alignment: .bottom) {
            contentArea
                #if os(iOS)
                .ignoresSafeArea(edges: .bottom)
                .ignoresSafeArea(edges: .top)
                #endif

            let expanded = isToolbarExpanded || isAddressBarFocused
            let backStyle = AnyShapeStyle(.clear)

            VStack(spacing: 0) {
                if showFindBar {
                    findBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if shouldShowTabStrip {
                    tabStrip
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                addressBar
            }
            .background(backStyle, ignoresSafeAreaEdges: .bottom)
            .background(
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size.height) { _, newHeight in
                        if expanded {
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
        .animation(.snappy(duration: 0.25), value: showFindBar)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: shouldShowTabStrip)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: isToolbarExpanded)
    }

    // MARK: - Tab Strip

    private var tabStrip: some View {
        let tabCount = max(1, viewModel.tabs.count)
        let staticSpace: CGFloat = 72.0
        let availableTabSpace = max(0, bottomContainerWidth - staticSpace)
        let totalSpacing = CGFloat(max(0, tabCount - 1)) * 2.0
        let calculatedWidth = max(110, (availableTabSpace - totalSpacing) / CGFloat(tabCount))
        
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(viewModel.tabs) { tab in
                        tabChip(for: tab, tabWidth: calculatedWidth)
                    }

                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            viewModel.addNewTab()
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background(Color.primary.opacity(0.05), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 2)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
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

    private func tabChip(for tab: BrowserTab, tabWidth: CGFloat) -> some View {
        let isSelected = tab.id == viewModel.selectedTabID

        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                viewModel.selectTab(tab.id)
            }
        } label: {
            HStack(spacing: 6) {
                if tab.currentURL != nil {
                    favicon(for: tab, size: 16)
                } else if tab.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(width: 16, height: 16)
                }

                Text(tab.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            viewModel.closeTab(tab.id)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .frame(width: 16, height: 16)
                            .background(
                                Circle().fill(Color.primary.opacity(isSelected ? 0.08 : 0.04))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, isSelected ? 6 : 10)
            .padding(.vertical, 10)
            .frame(width: tabWidth)
            .opacity(isSelected ? 1.0 : 0.75)
            .background(isSelected ? Color.primary.opacity(0.08) : Color.clear, in: .capsule)
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? (tab.currentURL != nil ? faviconColor(for: tab) : Color.accentColor).opacity(0.6) : Color.primary.opacity(0.1), lineWidth: isSelected ? 1.5 : 1.0)
            )
        }
        .buttonStyle(.plain)
        .id(tab.id)
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
                        .foregroundStyle(viewModel.isPrivate && !isAddressBarFocused ? .purple : (isAddressBarFocused ? Color.accentColor : Color.secondary))
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
                        Button { addressText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .font(.system(size: 15))
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
            .padding(.horizontal, expanded ? 16 : 14)
            .padding(.vertical, expanded ? 12 : 8)
            .frame(maxWidth: expanded ? .infinity : 200)
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
                if let tab = viewModel.selectedTab, tab.isLoading {
                    GeometryReader { geo in
                        Capsule()
                            .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, geo.size.width * tab.estimatedProgress), height: 2.5)
                            .shadow(color: .cyan.opacity(0.5), radius: 4, y: 0)
                            .animation(.easeInOut(duration: 0.3), value: tab.estimatedProgress)
                    }
                    .frame(height: 2.5)
                    .clipShape(Capsule())
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
                    .transition(.opacity)
                }
            }
            .overlay(
                Capsule()
                    .strokeBorder(
                        isAddressBarFocused ? Color.accentColor.opacity(0.5) : .clear,
                        lineWidth: 1.5
                    )
            )
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
        .padding(.top, expanded ? 8 : 2)
        .padding(.bottom, 8)
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
                                WebView(tab: tab, bottomBarHeight: viewModel.bottomBarHeight)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .clipped()
        .animation(.interactiveSpring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.18), value: addressBarOffset)
        .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.88, blendDuration: 0.18), value: viewModel.selectedTabID)
    }

    // MARK: - Start Page

    private var startPage: some View {
        ZStack {
            startPageBackground

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 70)

                    VStack(spacing: 10) {
                        Text(greeting)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [timeOfDayColors.0, timeOfDayColors.1],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        Text(formattedDate)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    startPageSearchField
                        .padding(.top, 32)
                        .padding(.horizontal, 28)

                    if !recentlyVisitedEntries.isEmpty {
                        recentlyVisitedSection
                    }

                    if !viewModel.bookmarkStore.bookmarks.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            sectionHeader("BOOKMARKS")

                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: favoritesColumnCount),
                                spacing: 16
                            ) {
                                ForEach(viewModel.bookmarkStore.bookmarks.prefix(favoritesColumnCount * 2)) { bookmark in
                                    bookmarkQuickLink(bookmark)
                                }
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 36)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader("FAVORITES")

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: favoritesColumnCount),
                            spacing: 16
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
                    .padding(.horizontal, 28)
                    .padding(.top, viewModel.bookmarkStore.bookmarks.isEmpty && recentlyVisitedEntries.isEmpty ? 40 : 32)

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: viewModel.bottomBarHeight)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary.opacity(0.8))
            .tracking(1.2)
            .padding(.horizontal, 4)
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
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("RECENTLY VISITED")
                .padding(.horizontal, 28)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(recentlyVisitedEntries) { entry in
                        Button {
                            viewModel.selectedTab?.load(entry.url)
                        } label: {
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(siteColor(for: entry.url).gradient)
                                    .frame(width: 52, height: 52)
                                    .overlay(
                                        Text(siteLetter(for: entry.url))
                                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                                            .foregroundStyle(.white)
                                    )
                                    .shadow(color: siteColor(for: entry.url).opacity(0.3), radius: 6, y: 3)

                                Text(hostLabel(for: entry.url))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 64)
                            }
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                .padding(.horizontal, 32)
            }
        }
        .padding(.top, 36)
    }

    private func hostLabel(for url: URL) -> String {
        guard let host = url.host else { return url.absoluteString }
        let cleaned = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return cleaned.components(separatedBy: ".").first?.capitalized ?? cleaned
    }

    private var startPageBackground: some View {
        let (c1, c2) = timeOfDayColors
        return ZStack {
            RadialGradient(
                colors: [c1.opacity(0.22), c1.opacity(0.06), .clear],
                center: .topLeading,
                startRadius: 60,
                endRadius: 500
            )

            RadialGradient(
                colors: [c2.opacity(0.15), c2.opacity(0.04), .clear],
                center: .bottomTrailing,
                startRadius: 40,
                endRadius: 450
            )

            RadialGradient(
                colors: [c1.opacity(0.06), c2.opacity(0.04), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 350
            )
        }
        .ignoresSafeArea()
    }

    private var startPageSearchField: some View {
        Button {
            isAddressBarFocused = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14, weight: .medium))

                Text("Search or enter website")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressableButtonStyle())
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
            viewModel.selectedTab?.load(bookmark.url)
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(color.opacity(0.1))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Text(siteLetter(for: bookmark.url))
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(color)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(color.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: color.opacity(0.18), radius: 8, y: 4)

                Text(bookmark.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func quickLink(_ name: String, url: String, icon: String, color: Color) -> some View {
        Button {
            if let url = URL(string: url) {
                viewModel.selectedTab?.load(url)
            }
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(color.opacity(0.1))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(color)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(color.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: color.opacity(0.18), radius: 8, y: 4)

                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        NavigationStack {
            Group {
                if viewModel.historyStore.entries.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock",
                        description: Text("Pages you visit will appear here.")
                    )
                } else {
                    List {
                        ForEach(viewModel.historyStore.groupedByDate, id: \.0) { group, entries in
                            Section(group) {
                                ForEach(entries) { entry in
                                    Button {
                                        viewModel.selectedTab?.load(entry.url)
                                        showHistory = false
                                    } label: {
                                        HStack(spacing: 10) {
                                            Circle()
                                                .fill(siteColor(for: entry.url).gradient)
                                                .frame(width: 28, height: 28)
                                                .overlay(
                                                    Text(siteLetter(for: entry.url))
                                                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                                                        .foregroundStyle(.white)
                                                )

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(entry.title)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Text(entry.url.host ?? entry.url.absoluteString)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }

                                            Spacer(minLength: 0)

                                            Text(entry.dateVisited, style: .time)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .swipeActions {
                                        Button("Delete", role: .destructive) {
                                            viewModel.historyStore.removeEntry(entry.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
        NavigationStack {
            Group {
                if viewModel.bookmarkStore.bookmarks.isEmpty {
                    ContentUnavailableView(
                        "No Bookmarks",
                        systemImage: "star",
                        description: Text("Tap the star in the address bar to bookmark a page.")
                    )
                } else {
                    List {
                        ForEach(viewModel.bookmarkStore.bookmarks) { bookmark in
                            Button {
                                viewModel.selectedTab?.load(bookmark.url)
                                showBookmarks = false
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(siteColor(for: bookmark.url).gradient)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Text(siteLetter(for: bookmark.url))
                                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                                .foregroundStyle(.white)
                                        )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bookmark.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(bookmark.url.host ?? bookmark.url.absoluteString)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    viewModel.bookmarkStore.removeBookmark(id: bookmark.id)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Bookmarks")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showBookmarks = false }
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
                Section("Browsing") {
                    settingsRow(
                        title: "Tab Count",
                        detail: "\(viewModel.tabs.count) open",
                        systemImage: "square.on.square"
                    )

                    settingsRow(
                        title: "Current Mode",
                        detail: viewModel.isPrivate ? "Private Browsing" : "Standard Browsing",
                        systemImage: viewModel.isPrivate ? "eye.slash" : "globe"
                    )

                    settingsRow(
                        title: "Toolbar",
                        detail: isToolbarExpanded ? "Expanded" : "Collapsed",
                        systemImage: "rectangle.tophalf.inset.filled"
                    )
                }

                Section("Library") {
                    Button {
                        showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showBookmarks = true
                        }
                    } label: {
                        settingsRow(
                            title: "Bookmarks",
                            detail: "\(viewModel.bookmarkStore.bookmarks.count) saved",
                            systemImage: "star"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showHistory = true
                        }
                    } label: {
                        settingsRow(
                            title: "History",
                            detail: "\(viewModel.historyStore.entries.count) visits",
                            systemImage: "clock.arrow.circlepath"
                        )
                    }
                    .buttonStyle(.plain)
                }

                Section("Actions") {
                    Button(role: .destructive) {
                        viewModel.historyStore.clearHistory()
                    } label: {
                        Label("Clear History", systemImage: "trash")
                    }
                    .disabled(viewModel.historyStore.entries.isEmpty)

                    Button(role: .destructive) {
                        viewModel.closeAllTabs()
                    } label: {
                        Label("Close All Tabs", systemImage: "xmark.square")
                    }
                    .disabled(viewModel.tabs.count <= 1 && viewModel.selectedTab?.currentURL == nil)
                }

                Section("About") {
                    settingsRow(
                        title: "App",
                        detail: "Browser Prototype",
                        systemImage: "app"
                    )

                    settingsRow(
                        title: "Version",
                        detail: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                        systemImage: "number"
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showSettings = false }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    // MARK: - Helpers

    private func settingsRow(title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
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
