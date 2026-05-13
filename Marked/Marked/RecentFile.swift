import Foundation
import SwiftData

@Model
final class RecentFile {
    @Attribute(.unique) var id: UUID
    var name: String
    var bookmarkData: Data
    var lastOpened: Date
    var scrollProgress: Double
    var displayPath: String = ""
    /// Cached filesystem path of the last successful bookmark resolution.
    /// Lets `matchExistingRecent` do an O(1) string compare instead of
    /// resolving every recent's bookmark on each open.
    var resolvedPath: String = ""

    init(name: String, bookmarkData: Data, displayPath: String = "", resolvedPath: String = "") {
        self.id = UUID()
        self.name = name
        self.bookmarkData = bookmarkData
        self.lastOpened = Date()
        self.scrollProgress = 0
        self.displayPath = displayPath
        self.resolvedPath = resolvedPath
    }

    func resolveURL() -> (url: URL, isStale: Bool)? {
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            return (url, stale)
        } catch {
            return nil
        }
    }
}
