import SwiftUI

enum TabGroup: String, CaseIterable {
    case normal
    case privateMode

    var label: String {
        switch self {
        case .normal: return "Tabs"
        case .privateMode: return "Private"
        }
    }

    var icon: String {
        switch self {
        case .normal: return "square.on.square"
        case .privateMode: return "eye.slash"
        }
    }
}

@Observable
class BrowserViewModel {
    var activeGroup: TabGroup = .normal
    var topBarHeight: CGFloat = 60
    var normalTabs: [BrowserTab] = []
    var privateTabs: [BrowserTab] = []
    var normalSelectedID: UUID?
    var privateSelectedID: UUID?
    let bookmarkStore = BookmarkStore()
    let historyStore = HistoryStore()
    @ObservationIgnored private var closedTabs: [(title: String, url: URL)] = []

    private static let savedTabsKey = "savedTabURLs"
    private static let savedSelectedIndexKey = "savedSelectedTabIndex"

    var tabs: [BrowserTab] {
        get { activeGroup == .normal ? normalTabs : privateTabs }
        set {
            if activeGroup == .normal { normalTabs = newValue }
            else { privateTabs = newValue }
        }
    }

    var selectedTabID: UUID? {
        get { activeGroup == .normal ? normalSelectedID : privateSelectedID }
        set {
            if activeGroup == .normal { normalSelectedID = newValue }
            else { privateSelectedID = newValue }
        }
    }

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedTabID }
    }

    var canReopenTab: Bool {
        !closedTabs.isEmpty
    }

    var isPrivate: Bool {
        activeGroup == .privateMode
    }

    init() {
        restoreTabs()
    }

    func switchGroup(_ group: TabGroup) {
        guard group != activeGroup else { return }
        activeGroup = group
        if tabs.isEmpty {
            addNewTab()
        }
    }

    func addNewTab(url: URL? = nil) {
        let isPrivateTab = activeGroup == .privateMode
        let tab = BrowserTab(url: url, isPrivate: isPrivateTab)
        if !isPrivateTab {
            tab.onPageLoaded = { [weak self] title, url in
                self?.historyStore.recordVisit(title: title, url: url)
            }
            tab.onURLChanged = { [weak self] in
                self?.saveTabs()
            }
        }
        tab.onOpenInNewTab = { [weak self] url in
            self?.addNewTab(url: url)
        }
        tabs.append(tab)
        selectedTabID = tab.id
        if !isPrivateTab {
            saveTabs()
        }
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        let wasSelected = selectedTabID == id

        if let url = tab.currentURL, activeGroup == .normal {
            closedTabs.append((title: tab.title, url: url))
        }

        tabs.remove(at: index)

        if wasSelected {
            if tabs.isEmpty {
                addNewTab()
            } else {
                selectedTabID = tabs[min(index, tabs.count - 1)].id
            }
        }
        if activeGroup == .normal {
            saveTabs()
        }
    }

    func closeAllTabs() {
        let isNormal = activeGroup == .normal
        for tab in tabs {
            if let url = tab.currentURL, isNormal {
                closedTabs.append((title: tab.title, url: url))
            }
        }
        tabs.removeAll()
        addNewTab()
        if isNormal {
            saveTabs()
        }
    }

    func reopenLastClosedTab() {
        guard let last = closedTabs.popLast() else { return }
        if activeGroup == .privateMode { switchGroup(.normal) }
        addNewTab(url: last.url)
    }

    func duplicateSelectedTab() {
        guard let tab = selectedTab, let url = tab.currentURL else { return }
        addNewTab(url: url)
    }

    func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
        if activeGroup == .normal {
            saveTabs()
        }
    }

    func snapshotAllTabs() {
        for tab in tabs {
            tab.takeSnapshot()
        }
    }

    func selectTab(_ id: UUID) {
        selectedTab?.takeSnapshot()
        selectedTabID = id
        if activeGroup == .normal {
            saveTabs()
        }
    }

    // MARK: - Tab Persistence

    private func saveTabs() {
        let urls = normalTabs.compactMap { $0.currentURL?.absoluteString }
        let selectedIndex: Int
        if let selID = normalSelectedID,
           let idx = normalTabs.firstIndex(where: { $0.id == selID }) {
            selectedIndex = idx
        } else {
            selectedIndex = 0
        }
        UserDefaults.standard.set(urls, forKey: Self.savedTabsKey)
        UserDefaults.standard.set(selectedIndex, forKey: Self.savedSelectedIndexKey)
    }

    private func restoreTabs() {
        guard let urls = UserDefaults.standard.stringArray(forKey: Self.savedTabsKey),
              !urls.isEmpty else {
            addNewTab()
            return
        }

        let savedGroup = activeGroup
        activeGroup = .normal

        for urlString in urls {
            if let url = URL(string: urlString) {
                let tab = BrowserTab(url: url, isPrivate: false)
                tab.onPageLoaded = { [weak self] title, url in
                    self?.historyStore.recordVisit(title: title, url: url)
                }
                tab.onURLChanged = { [weak self] in
                    self?.saveTabs()
                }
                tab.onOpenInNewTab = { [weak self] url in
                    self?.addNewTab(url: url)
                }
                normalTabs.append(tab)
            }
        }

        // If no tabs were restored (all URLs invalid), add a blank one
        if normalTabs.isEmpty {
            activeGroup = savedGroup
            addNewTab()
            return
        }

        let selectedIndex = UserDefaults.standard.integer(forKey: Self.savedSelectedIndexKey)
        let clampedIndex = min(selectedIndex, normalTabs.count - 1)
        normalSelectedID = normalTabs[clampedIndex].id

        // Also add empty tabs that had no URL (new tabs)
        // We only persisted tabs with URLs, so if the user had a new tab open, we just have URL tabs

        activeGroup = savedGroup
    }

    func selectNextTab() {
        guard let currentID = selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == currentID }) else { return }
        
        if index == tabs.count - 1 {
            addNewTab()
        } else {
            selectedTabID = tabs[index + 1].id
        }
    }

    func selectPreviousTab() {
        guard let currentID = selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == currentID }) else { return }
        
        if index > 0 {
            selectedTabID = tabs[index - 1].id
        }
    }
}
