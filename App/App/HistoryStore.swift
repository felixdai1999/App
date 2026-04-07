import Foundation

struct HistoryEntry: Identifiable, Codable {
    let id: UUID
    var title: String
    var url: URL
    var dateVisited: Date

    init(id: UUID = UUID(), title: String, url: URL, dateVisited: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.dateVisited = dateVisited
    }
}

@Observable
class HistoryStore {
    private(set) var entries: [HistoryEntry] = []

    private static let storageKey = "browser_history"
    private static let maxEntries = 500

    private static let groupDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    init() {
        load()
    }

    func recordVisit(title: String, url: URL) {
        if let last = entries.first,
           last.url == url,
           Date().timeIntervalSince(last.dateVisited) < 5 {
            return
        }
        entries.insert(HistoryEntry(title: title, url: url), at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        save()
    }

    func removeEntry(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clearHistory() {
        entries.removeAll()
        save()
    }

    var groupedByDate: [(String, [HistoryEntry])] {
        let calendar = Calendar.current

        var groups: [String: [HistoryEntry]] = [:]
        var order: [String] = []

        for entry in entries {
            let key: String
            if calendar.isDateInToday(entry.dateVisited) {
                key = "Today"
            } else if calendar.isDateInYesterday(entry.dateVisited) {
                key = "Yesterday"
            } else {
                key = Self.groupDateFormatter.string(from: entry.dateVisited)
            }

            if groups[key] == nil {
                order.append(key)
            }
            groups[key, default: []].append(entry)
        }

        return order.map { ($0, groups[$0]!) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }
}
