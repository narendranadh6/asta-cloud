import Foundation

/// What plays next. Pure value logic (no audio), so it is unit tested on any platform.
///
/// Upcoming items always stay in three bands, in this order:
/// 1. songs the listener added (Play Next / Add to Queue),
/// 2. the rest of what they started from (a playlist, album or search results),
/// 3. Halo Flow suggestions, which only ever join at the end.
public struct PlaybackQueue: Sendable, Equatable, Codable {
    /// Why an item is in the queue.
    public enum Origin: String, Sendable, Codable, CaseIterable {
        case context, user, flow
    }

    /// One slot in the queue. The same track can appear twice, so slots have their own id.
    public struct Item: Sendable, Hashable, Identifiable, Codable {
        public let id: UUID
        public var track: Track
        public var origin: Origin
        /// Position in the original context, used to undo shuffle.
        public var order: Int

        public init(track: Track, origin: Origin = .context, order: Int = 0, id: UUID = UUID()) {
            self.id = id
            self.track = track
            self.origin = origin
            self.order = order
        }
    }

    public enum RepeatMode: String, Sendable, CaseIterable, Codable {
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
    /// What the listener started from, e.g. "Focus Mix" (shown as "Playing from …").
    public private(set) var contextTitle: String?
    private var nextOrder = 0

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

    /// Upcoming items in one band, in play order.
    public func upNext(_ origin: Origin) -> [Item] { upNext.filter { $0.origin == origin } }

    /// Replaces the queue and makes `startAt` current. Shuffle keeps the start track first.
    public mutating func replace<R: RandomNumberGenerator>(
        with tracks: [Track], startAt: Int = 0, title: String? = nil, using rng: inout R
    ) {
        items = tracks.enumerated().map { Item(track: $1, origin: .context, order: $0) }
        nextOrder = items.count
        contextTitle = title
        currentIndex = items.isEmpty ? nil : min(max(startAt, 0), items.count - 1)
        if isShuffled { shuffleUpcoming(using: &rng) }
    }

    public mutating func replace(with tracks: [Track], startAt: Int = 0, title: String? = nil) {
        var rng = SystemRandomNumberGenerator()
        replace(with: tracks, startAt: startAt, title: title, using: &rng)
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

    /// "Play Next": first in the listener's band.
    public mutating func playNext(_ track: Track) {
        insertUser([track], at: firstUpcomingIndex)
    }

    /// "Add to Queue": last in the listener's band, still ahead of the context and Flow.
    public mutating func enqueue(_ tracks: [Track]) {
        insertUser(tracks, at: endOfUserBand)
    }

    /// Halo Flow suggestions join at the very end and never displace anything.
    public mutating func appendFlow(_ tracks: [Track]) {
        let new = tracks.map { Item(track: $0, origin: .flow, order: takeOrder()) }
        items.append(contentsOf: new)
        if currentIndex == nil && !items.isEmpty { currentIndex = 0 }
    }

    /// Drops upcoming Flow suggestions (e.g. when Autoplay is turned off).
    public mutating func removeUpcomingFlow() {
        let start = firstUpcomingIndex
        items = Array(items[..<start]) + upNextAfterRemoving(origin: .flow, from: start)
    }

    /// Clears the songs the listener added; the context and Flow stay.
    public mutating func clearUserQueue() {
        let start = firstUpcomingIndex
        items = Array(items[..<start]) + upNextAfterRemoving(origin: .user, from: start)
    }

    /// Moves an upcoming item to the front of the listener's band ("Play Next" on a row).
    public mutating func moveToNext(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), index >= firstUpcomingIndex
        else { return }
        var item = items.remove(at: index)
        item.origin = .user
        items.insert(item, at: firstUpcomingIndex)
    }

    /// Swaps in a refreshed copy of a track (e.g. a new stream link), keeping its slot.
    public mutating func updateTrack(id: UUID, to track: Track) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].track = track
    }

    /// Removes an upcoming or past item. The current item can't be removed this way.
    public mutating func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), index != currentIndex else {
            return
        }
        items.remove(at: index)
        if let current = currentIndex, index < current { currentIndex = current - 1 }
    }

    /// Reorders items within one upcoming band (offsets are positions within that band).
    public mutating func move(in origin: Origin, from source: IndexSet, to destination: Int) {
        let base = firstUpcomingIndex
        let positions = items.indices.filter { $0 >= base && items[$0].origin == origin }
        var band = positions.map { items[$0] }
        let moving = source.sorted().filter { $0 < band.count }.map { band[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        for offset in source.sorted(by: >) where offset < band.count {
            band.remove(at: offset)
        }
        band.insert(contentsOf: moving, at: min(max(insertAt, 0), band.count))
        for (position, item) in zip(positions, band) { items[position] = item }
    }

    public mutating func setShuffle<R: RandomNumberGenerator>(_ on: Bool, using rng: inout R) {
        guard on != isShuffled else { return }
        isShuffled = on
        if on {
            shuffleUpcoming(using: &rng)
        } else {
            // Continue in the original order; the listener's band and Flow keep their places.
            reorderUpcomingContext { $0.sorted { $0.order < $1.order } }
        }
    }

    public mutating func setShuffle(_ on: Bool) {
        var rng = SystemRandomNumberGenerator()
        setShuffle(on, using: &rng)
    }

    public mutating func clear() {
        items = []
        currentIndex = nil
        contextTitle = nil
    }

    // MARK: Helpers

    private var firstUpcomingIndex: Int { (currentIndex ?? -1) + 1 }

    private var endOfUserBand: Int {
        var index = firstUpcomingIndex
        while index < items.count, items[index].origin == .user { index += 1 }
        return index
    }

    private mutating func takeOrder() -> Int {
        defer { nextOrder += 1 }
        return nextOrder
    }

    private mutating func insertUser(_ tracks: [Track], at index: Int) {
        let new = tracks.map { Item(track: $0, origin: .user, order: takeOrder()) }
        items.insert(contentsOf: new, at: min(index, items.count))
        if currentIndex == nil && !items.isEmpty { currentIndex = 0 }
    }

    private func upNextAfterRemoving(origin: Origin, from start: Int) -> [Item] {
        items[start...].filter { $0.origin != origin }
    }

    private mutating func shuffleUpcoming<R: RandomNumberGenerator>(using rng: inout R) {
        reorderUpcomingContext { $0.shuffled(using: &rng) }
    }

    /// Rewrites the order of upcoming context items in place, leaving the other bands alone.
    private mutating func reorderUpcomingContext(_ reorder: ([Item]) -> [Item]) {
        let positions = items.indices.filter {
            $0 >= firstUpcomingIndex && items[$0].origin == .context
        }
        let reordered = reorder(positions.map { items[$0] })
        for (position, item) in zip(positions, reordered) { items[position] = item }
    }
}
