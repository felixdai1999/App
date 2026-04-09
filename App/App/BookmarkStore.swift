import Foundation
import SwiftUI

struct Bookmark: Identifiable, Codable, Hashable {
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
class BookmarkStore {
    private(set) var bookmarks: [Bookmark] = []

    private static let storageKey = "browser_bookmarks"

    init() {
        load()
    }

    func addBookmark(title: String, url: URL) {
        guard !bookmarks.contains(where: { $0.url == url }) else { return }
        bookmarks.append(Bookmark(title: title, url: url))
        save()
    }

    func removeBookmark(url: URL) {
        bookmarks.removeAll { $0.url == url }
        save()
    }

    func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    func moveBookmark(from source: IndexSet, to destination: Int) {
        bookmarks.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func isBookmarked(_ url: URL?) -> Bool {
        guard let url else { return false }
        return bookmarks.contains { $0.url == url }
    }

    func toggleBookmark(title: String, url: URL) {
        if isBookmarked(url) {
            removeBookmark(url: url)
        } else {
            addBookmark(title: title, url: url)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    func clearForTesting() {
        bookmarks.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = decoded
        }
    }
}
