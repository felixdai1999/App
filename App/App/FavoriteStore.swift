import Foundation
import SwiftUI

struct Favorite: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var url: URL
    var dateAdded: Date

    init(id: UUID = UUID(), title: String, url: URL, dateAdded: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.dateAdded = dateAdded
    }
}

@Observable
class FavoriteStore {
    private(set) var favorites: [Favorite] = []

    private static let storageKey = "browser_favorites"

    init() {
        load()
        if favorites.isEmpty {
            setupDefaultFavorites()
        }
    }

    func addFavorite(title: String, url: URL) {
        guard !favorites.contains(where: { $0.url == url }) else { return }
        favorites.append(Favorite(title: title, url: url))
        save()
    }

    func removeFavorite(id: UUID) {
        favorites.removeAll { $0.id == id }
        save()
    }

    func moveFavorite(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([Favorite].self, from: data) {
            favorites = decoded
        }
    }

    private func setupDefaultFavorites() {
        let defaults = [
            ("Apple", "https://www.apple.com"),
            ("Google", "https://www.google.com"),
            ("GitHub", "https://www.github.com"),
            ("YouTube", "https://www.youtube.com"),
            ("Reddit", "https://www.reddit.com"),
            ("Wikipedia", "https://www.wikipedia.org"),
            ("Twitter", "https://www.x.com"),
            ("News", "https://news.ycombinator.com")
        ]
        
        for (name, urlString) in defaults {
            if let url = URL(string: urlString) {
                favorites.append(Favorite(title: name, url: url))
            }
        }
        save()
    }
}
