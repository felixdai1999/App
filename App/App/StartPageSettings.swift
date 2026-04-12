import SwiftUI

enum StartPageSection: String, CaseIterable, Codable, Identifiable {
    case recentlyVisited
    case bookmarks
    case favorites

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recentlyVisited: return "Recently Visited"
        case .bookmarks: return "Bookmarks"
        case .favorites: return "Favorites"
        }
    }

    var icon: String {
        switch self {
        case .recentlyVisited: return "clock.fill"
        case .bookmarks: return "star.fill"
        case .favorites: return "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .recentlyVisited: return .blue
        case .bookmarks: return .yellow
        case .favorites: return .pink
        }
    }
}

enum QuickActionItem: String, CaseIterable, Codable, Identifiable {
    /// Declaration order is the default quick-action order for new installs and `allCases`.
    case search
    case favorites
    case bookmarks
    case history
    case tabOverview
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .search: return "Search"
        case .favorites: return "Favorites"
        case .bookmarks: return "Bookmarks"
        case .history: return "History"
        case .tabOverview: return "Tabs"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .favorites: return "heart.fill"
        case .bookmarks: return "star.fill"
        case .history: return "clock.fill"
        case .tabOverview: return "square.on.square"
        case .settings: return "gearshape.fill"
        }
    }
}

enum StartPageGradientPreset: String, CaseIterable, Codable, Identifiable {
    case monochrome
    case dynamic
    case ocean
    case sunset
    case aurora
    case midnight
    case dawn
    case tropical
    case candy
    case neon

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monochrome: return "Monochrome"
        case .dynamic: return "Dynamic"
        case .ocean: return "Ocean"
        case .sunset: return "Sunset"
        case .aurora: return "Aurora"
        case .midnight: return "Midnight"
        case .dawn: return "Dawn"
        case .tropical: return "Tropical"
        case .candy: return "Candy"
        case .neon: return "Neon"
        }
    }
}

@Observable
class StartPageSettings {
    var showGreeting: Bool {
        didSet { save() }
    }

    var showQuickActions: Bool {
        didSet { save() }
    }

    var sectionVisibility: [StartPageSection: Bool] {
        didSet { save() }
    }

    var sectionOrder: [StartPageSection] {
        didSet { save() }
    }

    var quickActionVisibility: [QuickActionItem: Bool] {
        didSet { save() }
    }

    var quickActionOrder: [QuickActionItem] {
        didSet { save() }
    }

    var gradientPreset: StartPageGradientPreset {
        didSet { save() }
    }

    private static let greetingKey = "startPage_showGreeting"
    private static let quickActionsEnabledKey = "startPage_showQuickActions"
    private static let visibilityKey = "startPage_sectionVisibility"
    private static let orderKey = "startPage_sectionOrder"
    private static let quickActionsVisibilityKey = "startPage_quickActionVisibility"
    private static let quickActionsOrderKey = "startPage_quickActionOrder"
    private static let gradientPresetKey = "startPage_gradientPreset"

    init() {
        let defaults = UserDefaults.standard

        self.showGreeting = defaults.object(forKey: Self.greetingKey) as? Bool ?? true
        self.showQuickActions = defaults.object(forKey: Self.quickActionsEnabledKey) as? Bool ?? true

        // Section Visibility
        if let data = defaults.data(forKey: Self.visibilityKey),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            var vis: [StartPageSection: Bool] = [:]
            for section in StartPageSection.allCases {
                vis[section] = decoded[section.rawValue] ?? true
            }
            self.sectionVisibility = vis
        } else {
            var vis: [StartPageSection: Bool] = [:]
            for section in StartPageSection.allCases { vis[section] = true }
            self.sectionVisibility = vis
        }

        // Section Order
        if let data = defaults.data(forKey: Self.orderKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            let ordered = decoded.compactMap { StartPageSection(rawValue: $0) }
            let missing = StartPageSection.allCases.filter { !ordered.contains($0) }
            self.sectionOrder = ordered + missing
        } else {
            self.sectionOrder = StartPageSection.allCases
        }

        // Quick Action Visibility
        if let data = defaults.data(forKey: Self.quickActionsVisibilityKey),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            var vis: [QuickActionItem: Bool] = [:]
            for item in QuickActionItem.allCases {
                vis[item] = decoded[item.rawValue] ?? true
            }
            self.quickActionVisibility = vis
        } else {
            var vis: [QuickActionItem: Bool] = [:]
            for item in QuickActionItem.allCases { vis[item] = true }
            self.quickActionVisibility = vis
        }

        // Quick Action Order
        if let data = defaults.data(forKey: Self.quickActionsOrderKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            let ordered = decoded.compactMap { QuickActionItem(rawValue: $0) }
            let missing = QuickActionItem.allCases.filter { !ordered.contains($0) }
            self.quickActionOrder = ordered + missing
        } else {
            self.quickActionOrder = QuickActionItem.allCases
        }

        if let raw = defaults.string(forKey: Self.gradientPresetKey),
           let preset = StartPageGradientPreset(rawValue: raw) {
            self.gradientPreset = preset
        } else {
            self.gradientPreset = .monochrome
        }
    }

    func isSectionVisible(_ section: StartPageSection) -> Bool {
        sectionVisibility[section] ?? true
    }

    func setSectionVisible(_ section: StartPageSection, _ visible: Bool) {
        sectionVisibility[section] = visible
    }

    func moveSection(from source: IndexSet, to destination: Int) {
        sectionOrder.move(fromOffsets: source, toOffset: destination)
    }

    func isQuickActionVisible(_ item: QuickActionItem) -> Bool {
        quickActionVisibility[item] ?? true
    }

    func setQuickActionVisible(_ item: QuickActionItem, _ visible: Bool) {
        quickActionVisibility[item] = visible
    }

    func moveQuickAction(from source: IndexSet, to destination: Int) {
        quickActionOrder.move(fromOffsets: source, toOffset: destination)
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(showGreeting, forKey: Self.greetingKey)
        defaults.set(showQuickActions, forKey: Self.quickActionsEnabledKey)

        let visDict = Dictionary(uniqueKeysWithValues: sectionVisibility.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(visDict) {
            defaults.set(data, forKey: Self.visibilityKey)
        }

        let orderStrings = sectionOrder.map(\.rawValue)
        if let data = try? JSONEncoder().encode(orderStrings) {
            defaults.set(data, forKey: Self.orderKey)
        }

        let qaVisDict = Dictionary(uniqueKeysWithValues: quickActionVisibility.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(qaVisDict) {
            defaults.set(data, forKey: Self.quickActionsVisibilityKey)
        }

        let qaOrderStrings = quickActionOrder.map(\.rawValue)
        if let data = try? JSONEncoder().encode(qaOrderStrings) {
            defaults.set(data, forKey: Self.quickActionsOrderKey)
        }

        defaults.set(gradientPreset.rawValue, forKey: Self.gradientPresetKey)
    }
}
