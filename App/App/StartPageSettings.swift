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

@Observable
class StartPageSettings {
    var showGreeting: Bool {
        didSet { save() }
    }

    var sectionVisibility: [StartPageSection: Bool] {
        didSet { save() }
    }

    var sectionOrder: [StartPageSection] {
        didSet { save() }
    }

    private static let greetingKey = "startPage_showGreeting"
    private static let visibilityKey = "startPage_sectionVisibility"
    private static let orderKey = "startPage_sectionOrder"

    init() {
        let defaults = UserDefaults.standard

        self.showGreeting = defaults.object(forKey: Self.greetingKey) as? Bool ?? true

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

        if let data = defaults.data(forKey: Self.orderKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            let ordered = decoded.compactMap { StartPageSection(rawValue: $0) }
            let missing = StartPageSection.allCases.filter { !ordered.contains($0) }
            self.sectionOrder = ordered + missing
        } else {
            self.sectionOrder = StartPageSection.allCases
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

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(showGreeting, forKey: Self.greetingKey)

        let visDict = Dictionary(uniqueKeysWithValues: sectionVisibility.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(visDict) {
            defaults.set(data, forKey: Self.visibilityKey)
        }

        let orderStrings = sectionOrder.map(\.rawValue)
        if let data = try? JSONEncoder().encode(orderStrings) {
            defaults.set(data, forKey: Self.orderKey)
        }
    }
}
