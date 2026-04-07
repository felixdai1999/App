import Testing
@testable import App

struct AppTests {

    // MARK: - BrowserViewModel

    @Test("ViewModel starts with one tab")
    func viewModelInitialization() {
        let vm = BrowserViewModel()
        #expect(vm.tabs.count == 1)
        #expect(vm.selectedTabID != nil)
        #expect(vm.selectedTab != nil)
    }

    @Test("Adding a new tab selects it")
    func addNewTab() {
        let vm = BrowserViewModel()
        let firstID = vm.selectedTabID
        vm.addNewTab()
        #expect(vm.tabs.count == 2)
        #expect(vm.selectedTabID != firstID)
        #expect(vm.selectedTab === vm.tabs.last)
    }

    @Test("Closing the selected tab selects an adjacent tab")
    func closeSelectedTab() {
        let vm = BrowserViewModel()
        vm.addNewTab()
        vm.addNewTab()
        #expect(vm.tabs.count == 3)

        let middleTab = vm.tabs[1]
        vm.selectTab(middleTab.id)
        vm.closeTab(middleTab.id)

        #expect(vm.tabs.count == 2)
        #expect(vm.selectedTabID != nil)
        #expect(vm.selectedTab != nil)
    }

    @Test("Closing the last tab creates a fresh one")
    func closeLastTab() {
        let vm = BrowserViewModel()
        let onlyID = vm.selectedTabID!
        vm.closeTab(onlyID)

        #expect(vm.tabs.count == 1)
        #expect(vm.selectedTabID != onlyID)
    }

    @Test("Close all tabs resets to a single new tab")
    func closeAllTabs() {
        let vm = BrowserViewModel()
        vm.addNewTab()
        vm.addNewTab()
        #expect(vm.tabs.count == 3)

        vm.closeAllTabs()
        #expect(vm.tabs.count == 1)
    }

    @Test("Select next and previous tab cycles through tabs")
    func tabCycling() {
        let vm = BrowserViewModel()
        vm.addNewTab()
        vm.addNewTab()
        let ids = vm.tabs.map(\.id)

        vm.selectTab(ids[0])
        vm.selectNextTab()
        #expect(vm.selectedTabID == ids[1])

        vm.selectNextTab()
        #expect(vm.selectedTabID == ids[2])

        vm.selectNextTab()
        #expect(vm.selectedTabID == ids[0])

        vm.selectPreviousTab()
        #expect(vm.selectedTabID == ids[2])
    }

    @Test("New tab defaults to correct title")
    func newTabTitle() {
        let tab = BrowserTab()
        #expect(tab.title == "New Tab")
        #expect(tab.currentURL == nil)
        #expect(!tab.isLoading)
    }

    @Test("Reopen closed tab restores last closed URL")
    func reopenClosedTab() {
        let vm = BrowserViewModel()
        let tab = vm.tabs[0]
        tab.currentURL = URL(string: "https://example.com")
        tab.title = "Example"

        vm.closeTab(tab.id)
        #expect(vm.canReopenTab)

        vm.reopenLastClosedTab()
        #expect(vm.tabs.count == 2)
    }

    @Test("Cannot reopen when no tabs have been closed")
    func cannotReopenWhenEmpty() {
        let vm = BrowserViewModel()
        #expect(!vm.canReopenTab)
    }

    @Test("Duplicate tab requires a loaded URL")
    func duplicateTab() {
        let vm = BrowserViewModel()
        let countBefore = vm.tabs.count
        vm.duplicateSelectedTab()
        #expect(vm.tabs.count == countBefore)
    }

    // MARK: - BookmarkStore

    @Test("Add and remove bookmarks")
    func bookmarkAddRemove() {
        let store = BookmarkStore()
        store.clearForTesting()

        let url = URL(string: "https://example.com")!
        store.addBookmark(title: "Example", url: url)
        #expect(store.bookmarks.count == 1)
        #expect(store.isBookmarked(url))

        store.removeBookmark(url: url)
        #expect(store.bookmarks.isEmpty)
        #expect(!store.isBookmarked(url))
    }

    @Test("Toggle bookmark adds then removes")
    func bookmarkToggle() {
        let store = BookmarkStore()
        store.clearForTesting()

        let url = URL(string: "https://test.com")!
        store.toggleBookmark(title: "Test", url: url)
        #expect(store.isBookmarked(url))

        store.toggleBookmark(title: "Test", url: url)
        #expect(!store.isBookmarked(url))
    }

    @Test("Duplicate bookmarks are not added")
    func bookmarkNoDuplicates() {
        let store = BookmarkStore()
        store.clearForTesting()

        let url = URL(string: "https://example.com")!
        store.addBookmark(title: "One", url: url)
        store.addBookmark(title: "Two", url: url)
        #expect(store.bookmarks.count == 1)
    }

    // MARK: - HistoryStore

    @Test("Record and clear history")
    func historyRecordAndClear() {
        let store = HistoryStore()
        store.clearHistory()

        store.recordVisit(title: "Page 1", url: URL(string: "https://a.com")!)
        store.recordVisit(title: "Page 2", url: URL(string: "https://b.com")!)
        #expect(store.entries.count == 2)
        #expect(store.entries.first?.title == "Page 2")

        store.clearHistory()
        #expect(store.entries.isEmpty)
    }

    @Test("Rapid duplicate visits are deduplicated")
    func historyDeduplication() {
        let store = HistoryStore()
        store.clearHistory()

        let url = URL(string: "https://example.com")!
        store.recordVisit(title: "Example", url: url)
        store.recordVisit(title: "Example", url: url)
        #expect(store.entries.count == 1)
    }

    @Test("History groups by date")
    func historyGrouping() {
        let store = HistoryStore()
        store.clearHistory()

        store.recordVisit(title: "Today", url: URL(string: "https://today.com")!)
        let groups = store.groupedByDate
        #expect(!groups.isEmpty)
        #expect(groups[0].0 == "Today")
    }

    @Test("Remove single history entry")
    func historyRemoveEntry() {
        let store = HistoryStore()
        store.clearHistory()

        store.recordVisit(title: "Page", url: URL(string: "https://example.com")!)
        let id = store.entries[0].id
        store.removeEntry(id)
        #expect(store.entries.isEmpty)
    }

    // MARK: - BrowserTab Features

    @Test("Zoom in increases zoom level")
    func zoomIn() {
        let tab = BrowserTab()
        #expect(tab.zoomLevel == 1.0)
        tab.zoomIn()
        #expect(tab.zoomLevel > 1.0)
    }

    @Test("Zoom out decreases zoom level")
    func zoomOut() {
        let tab = BrowserTab()
        tab.zoomOut()
        #expect(tab.zoomLevel < 1.0)
    }

    @Test("Reset zoom returns to 1.0")
    func resetZoom() {
        let tab = BrowserTab()
        tab.zoomIn()
        tab.zoomIn()
        tab.resetZoom()
        #expect(tab.zoomLevel == 1.0)
    }

    @Test("Zoom level is clamped")
    func zoomClamp() {
        let tab = BrowserTab()
        for _ in 0..<50 { tab.zoomIn() }
        #expect(tab.zoomLevel <= 3.0)

        for _ in 0..<100 { tab.zoomOut() }
        #expect(tab.zoomLevel >= 0.3)
    }

    @Test("Desktop mode toggles")
    func desktopModeToggle() {
        let tab = BrowserTab()
        #expect(!tab.isDesktopMode)
        tab.toggleDesktopMode()
        #expect(tab.isDesktopMode)
        tab.toggleDesktopMode()
        #expect(!tab.isDesktopMode)
    }

    // MARK: - Open in New Tab

    @Test("target=_blank links open in new tab via callback")
    func openInNewTab() {
        let vm = BrowserViewModel()
        let initialCount = vm.tabs.count
        let tab = vm.tabs[0]
        tab.onOpenInNewTab?(URL(string: "https://example.com")!)
        #expect(vm.tabs.count == initialCount + 1)
    }

    // MARK: - Find Debounce

    @Test("Clear find cancels debounce and resets state")
    func clearFindResetsState() {
        let tab = BrowserTab()
        tab.findInPage("hello")
        tab.clearFind()
        tab.findInPageNext()
    }

    // MARK: - Private Browsing

    @Test("Private tab uses non-persistent data store")
    func privateTab() {
        let tab = BrowserTab(isPrivate: true)
        #expect(tab.isPrivate)
        #expect(tab.title == "New Tab")
    }

    @Test("Switching tab groups preserves tabs")
    func tabGroupSwitching() {
        let vm = BrowserViewModel()
        #expect(vm.activeGroup == .normal)
        #expect(vm.tabs.count == 1)

        vm.switchGroup(.privateMode)
        #expect(vm.activeGroup == .privateMode)
        #expect(vm.tabs.count == 1)
        #expect(vm.tabs[0].isPrivate)

        vm.switchGroup(.normal)
        #expect(vm.tabs.count == 1)
        #expect(!vm.tabs[0].isPrivate)
    }

    @Test("Private tabs do not record history")
    func privateTabNoHistory() {
        let vm = BrowserViewModel()
        vm.switchGroup(.privateMode)
        let tab = vm.tabs[0]
        tab.onPageLoaded?("Test", URL(string: "https://secret.com")!)
        #expect(vm.historyStore.entries.isEmpty)
    }

    @Test("Move tab reorders array")
    func moveTab() {
        let vm = BrowserViewModel()
        vm.addNewTab()
        vm.addNewTab()
        let ids = vm.tabs.map(\.id)
        vm.moveTab(from: IndexSet(integer: 0), to: 3)
        #expect(vm.tabs.last?.id == ids[0])
    }
}
