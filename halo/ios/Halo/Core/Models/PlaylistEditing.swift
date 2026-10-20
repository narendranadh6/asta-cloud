import Foundation

/// Pure, value-type playlist editing used by the AI draft editor, Playlist Studio and
/// local playlists. Kept free of SwiftUI/SwiftData so it is unit tested on any platform.
public struct EditableQueue<Element: Identifiable & Sendable>: Sendable where Element.ID: Sendable {
    public private(set) var items: [Element]

    public init(_ items: [Element] = []) {
        self.items = items
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    /// Mirrors SwiftUI's `onMove(perform:)` semantics (destination is pre-removal index).
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty, destination >= 0, destination <= items.count,
              source.allSatisfy({ $0 >= 0 && $0 < items.count }) else { return }
        let moving = source.map { items[$0] }
        let insertion = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) {
            items.remove(at: index)
        }
        items.insert(contentsOf: moving, at: max(0, min(insertion, items.count)))
    }

    public mutating func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where index >= 0 && index < items.count {
            items.remove(at: index)
        }
    }

    public mutating func remove(id: Element.ID) {
        items.removeAll { $0.id == id }
    }

    /// Inserts at `position` (clamped). Returns false if an element with the same id exists.
    @discardableResult
    public mutating func insert(_ element: Element, at position: Int? = nil) -> Bool {
        guard !items.contains(where: { $0.id == element.id }) else { return false }
        let index = min(max(position ?? items.count, 0), items.count)
        items.insert(element, at: index)
        return true
    }

    public mutating func replaceAll(_ newItems: [Element]) {
        items = newItems
    }
}

public enum DurationFormatter {
    /// "3:33", "1:02:05"
    public static func clock(_ seconds: Int?) -> String {
        guard let seconds, seconds >= 0 else { return "–:––" }
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// "about 1 hr 15 min", "45 min"
    public static func approximate(_ seconds: Int) -> String {
        let minutes = Int((Double(max(seconds, 0)) / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}

/// Plans the minimal remote operations to make a backend playlist match local order.
public enum PlaylistSyncPlanner {
    public struct RemoteEntry: Equatable, Sendable {
        public var itemID: UUID
        public var videoID: String
        public init(itemID: UUID, videoID: String) {
            self.itemID = itemID
            self.videoID = videoID
        }
    }

    public struct Plan: Equatable, Sendable {
        public var removals: [UUID]
        public var additions: [String]
    }

    /// Matches entries as multisets so duplicate videos are handled correctly.
    public static func plan(local: [String], remote: [RemoteEntry]) -> Plan {
        var available: [String: [UUID]] = [:]
        for entry in remote {
            available[entry.videoID, default: []].append(entry.itemID)
        }
        var additions: [String] = []
        for videoID in local {
            if var ids = available[videoID], !ids.isEmpty {
                ids.removeFirst()
                available[videoID] = ids
            } else {
                additions.append(videoID)
            }
        }
        let leftover = Set(available.values.flatMap { $0 })
        let removals = remote.map(\.itemID).filter { leftover.contains($0) }
        return Plan(removals: removals, additions: additions)
    }

    /// After removals/additions, the remote item ids ordered to match `local`.
    public static func order(local: [String], remote: [RemoteEntry]) -> [UUID]? {
        var pools: [String: [UUID]] = [:]
        for entry in remote {
            pools[entry.videoID, default: []].append(entry.itemID)
        }
        var ordered: [UUID] = []
        for videoID in local {
            guard var ids = pools[videoID], !ids.isEmpty else { return nil }
            ordered.append(ids.removeFirst())
            pools[videoID] = ids
        }
        return ordered.count == remote.count ? ordered : nil
    }
}
