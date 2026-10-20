import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

private struct Item: Identifiable, Sendable, Equatable {
    let id: String
}

final class PlaylistEditingTests: XCTestCase {
    private func queue(_ ids: String...) -> EditableQueue<Item> {
        EditableQueue(ids.map(Item.init))
    }

    private func ids(_ q: EditableQueue<Item>) -> [String] { q.items.map(\.id) }

    func testMoveDownMatchesSwiftUISemantics() {
        var q = queue("a", "b", "c", "d")
        q.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)  // after "c"
        XCTAssertEqual(ids(q), ["b", "c", "a", "d"])
    }

    func testMoveUp() {
        var q = queue("a", "b", "c", "d")
        q.move(fromOffsets: IndexSet(integer: 3), toOffset: 1)
        XCTAssertEqual(ids(q), ["a", "d", "b", "c"])
    }

    func testMoveToEndAndMultiple() {
        var q = queue("a", "b", "c", "d", "e")
        q.move(fromOffsets: IndexSet([0, 2]), toOffset: 5)
        XCTAssertEqual(ids(q), ["b", "d", "e", "a", "c"])
    }

    func testInvalidMoveIsIgnored() {
        var q = queue("a", "b")
        q.move(fromOffsets: IndexSet(integer: 5), toOffset: 0)
        q.move(fromOffsets: IndexSet(integer: 0), toOffset: 9)
        XCTAssertEqual(ids(q), ["a", "b"])
    }

    func testRemoveAndInsert() {
        var q = queue("a", "b", "c")
        q.remove(atOffsets: IndexSet([0, 2, 7]))
        XCTAssertEqual(ids(q), ["b"])
        XCTAssertTrue(q.insert(Item(id: "z"), at: 0))
        XCTAssertFalse(q.insert(Item(id: "z")))  // no duplicates
        XCTAssertTrue(q.insert(Item(id: "y"), at: 99))
        XCTAssertEqual(ids(q), ["z", "b", "y"])
        q.remove(id: "b")
        XCTAssertEqual(ids(q), ["z", "y"])
    }

    func testDurationFormatting() {
        XCTAssertEqual(DurationFormatter.clock(213), "3:33")
        XCTAssertEqual(DurationFormatter.clock(3725), "1:02:05")
        XCTAssertEqual(DurationFormatter.clock(nil), "–:––")
        XCTAssertEqual(DurationFormatter.approximate(2700), "45 min")
        XCTAssertEqual(DurationFormatter.approximate(4500), "1 hr 15 min")
        XCTAssertEqual(DurationFormatter.approximate(7200), "2 hr")
    }

    func testSyncPlannerHandlesDuplicatesAndOrder() {
        let a1 = UUID(), b1 = UUID(), a2 = UUID(), c1 = UUID()
        let remote = [
            PlaylistSyncPlanner.RemoteEntry(itemID: a1, trackID: "aaaaaaaaaaa"),
            PlaylistSyncPlanner.RemoteEntry(itemID: b1, trackID: "bbbbbbbbbbb"),
            PlaylistSyncPlanner.RemoteEntry(itemID: a2, trackID: "aaaaaaaaaaa"),
            PlaylistSyncPlanner.RemoteEntry(itemID: c1, trackID: "ccccccccccc"),
        ]
        let local = ["ccccccccccc", "aaaaaaaaaaa", "ddddddddddd"]
        let plan = PlaylistSyncPlanner.plan(local: local, remote: remote)
        XCTAssertEqual(plan.additions, ["ddddddddddd"])
        XCTAssertEqual(Set(plan.removals), [b1, a2])

        let d1 = UUID()
        let afterSync = [
            PlaylistSyncPlanner.RemoteEntry(itemID: a1, trackID: "aaaaaaaaaaa"),
            PlaylistSyncPlanner.RemoteEntry(itemID: c1, trackID: "ccccccccccc"),
            PlaylistSyncPlanner.RemoteEntry(itemID: d1, trackID: "ddddddddddd"),
        ]
        XCTAssertEqual(PlaylistSyncPlanner.order(local: local, remote: afterSync), [c1, a1, d1])
        XCTAssertNil(PlaylistSyncPlanner.order(local: ["aaaaaaaaaaa"], remote: afterSync))
    }
}
