import Foundation

/// What plays next. Pure value logic (no audio), so it is unit tested on any platform.
public struct PlaybackQueue: Sendable, Equatable {
    /// One slot in the queue. The same track can appear twice, so slots have their own id.
    public struct Item: Sendable, Hashable, Identifiable {
        public let id: UUID
        public var track: Track

        public init(track: Track, id: UUID = UUID()) {
            self.id = id
            self.track = track
        }
    }

    public enum RepeatMode: String, Sendable, CaseIterable {
        case off, all, one

        public var next: RepeatMode {
            switch self {
            case .off: .all
            case .all: .one
            case .one: .off
            }
        }
    }

    public private(set) var items: [Item] = []
    public private(set) var currentIndex: Int?
    public var repeatMode: RepeatMode = .off
    public private(set) var isShuffled = false
    /// The order before shuffling, restored when shuffle is turned off.
    private var unshuffledOrder: [UUID] = []

    public init() {}

    public var current: Item? { currentIndex.map { items[$0] } }
    public var upNext: [Item] {
        guard let index = currentIndex else { return items }
        return Array(items[(index + 1)...])
    }
    public var history: [Item] {
        guard let index = currentIndex else { return [] }
        return Array(items[..<index])
    }
    public var isEmpty: Bool { items.isEmpty }

    /// Replaces the queue and makes `startAt` current. Shuffle keeps the start track first.
    public mutating func replace<R: RandomNumberGenerator>(
        with tracks: [Track], startAt: Int = 0, using rng: inout R
    ) {
        items = tracks.map { Item(track: $0) }
        currentIndex = items.isEmpty ? nil : min(max(startAt, 0), items.count - 1)
        unshuffledOrder = items.map(\.id)
        if isShuffled { shuffleUpcoming(using: &rng) }
    }

    public mutating func replace(with tracks: [Track], startAt: Int = 0) {
        var rng = SystemRandomNumberGenerator()
        replace(with: tracks, startAt: startAt, using: &rng)
    }

    /// Moves to the following item. `automatic` is true when a track finished by itself, in
    /// which case "repeat one" replays it. Returns nil at the end of the queue.
    @discardableResult
    public mutating func advance(automatic: Bool) -> Item? {
        guard let index = currentIndex else { return nil }
        if automatic && repeatMode == .one { return items[index] }
        if index + 1 < items.count {
            currentIndex = index + 1
        } else if repeatMode != .off && !items.isEmpty {
            currentIndex = 0
        } else {
            return nil
        }
        return current
    }

    /// Moves to the previous item (or the last one when repeating). Nil at the start.
    @discardableResult
    public mutating func goBack() -> Item? {
        guard let index = currentIndex else { return nil }
        if index > 0 {
            currentIndex = index - 1
        } else if repeatMode == .all && !items.isEmpty {
            currentIndex = items.count - 1
        } else {
            return nil
        }
        return current
    }

    @discardableResult
    public mutating func jump(to id: UUID) -> Item? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        currentIndex = index
        return current
    }

    /// Inserts right after the current item.
    public mutating func playNext(_ track: Track) {
        let item = Item(track: track)
        let index = currentIndex.map { $0 + 1 } ?? 0
        items.insert(item, at: index)
        unshuffledOrder.append(item.id)
        if currentIndex == nil { currentIndex = 0 }
    }

    public mutating func append(_ tracks: [Track]) {
        let new = tracks.map { Item(track: $0) }
        items.append(contentsOf: new)
        unshuffledOrder.append(contentsOf: new.map(\.id))
        if currentIndex == nil && !items.isEmpty { currentIndex = 0 }
    }

    /// Removes an upcoming or past item. The current item can't be removed this way.
    public mutating func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), index != currentIndex else {
            return
        }
        items.remove(at: index)
        unshuffledOrder.removeAll { $0 == id }
        if let current = currentIndex, index < current { currentIndex = current - 1 }
    }

    /// Reorders the upcoming items (offsets are positions within `upNext`).
    public mutating func moveUpNext(from source: IndexSet, to destination: Int) {
        let base = (currentIndex ?? -1) + 1
        var upcoming = Array(items[base...])
        let moving = source.sorted().filter { $0 < upcoming.count }.map { upcoming[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        for offset in source.sorted(by: >) where offset < upcoming.count {
            upcoming.remove(at: offset)
        }
        upcoming.insert(contentsOf: moving, at: min(max(insertAt, 0), upcoming.count))
        items.replaceSubrange(base..., with: upcoming)
    }

    public mutating func setShuffle<R: RandomNumberGenerator>(_ on: Bool, using rng: inout R) {
        guard on != isShuffled else { return }
        isShuffled = on
        if on {
            unshuffledOrder = items.map(\.id)
            shuffleUpcoming(using: &rng)
        } else {
            let currentID = current?.id
            let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            items = unshuffledOrder.compactMap { byID[$0] }
            currentIndex = currentID.flatMap { id in items.firstIndex { $0.id == id } }
        }
    }

    public mutating func setShuffle(_ on: Bool) {
        var rng = SystemRandomNumberGenerator()
        setShuffle(on, using: &rng)
    }

    public mutating func clear() {
        items = []
        currentIndex = nil
        unshuffledOrder = []
    }

    private mutating func shuffleUpcoming<R: RandomNumberGenerator>(using rng: inout R) {
        let base = (currentIndex ?? -1) + 1
        guard base < items.count else { return }
        items[base...].shuffle(using: &rng)
    }
}
