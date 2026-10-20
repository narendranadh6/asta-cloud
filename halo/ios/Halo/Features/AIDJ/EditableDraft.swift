import Foundation

/// Editable form of an AI-generated playlist. Every track came from the backend's catalog;
/// editing only reorders/removes them.
struct EditableDraft: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var explanation: String
    var planner: String
    var sources: [String]
    var sessionID: UUID?
    var warnings: [String]
    var queries: [String]
    var targetSeconds: Int
    var queue: EditableQueue<RecommendedTrack>

    init(_ draft: PlaylistDraft) {
        title = draft.title
        explanation = draft.explanation
        planner = draft.planner
        sources = draft.sources
        sessionID = draft.sessionId
        warnings = draft.warnings
        queries = draft.queries
        targetSeconds = draft.targetDurationSeconds
        queue = EditableQueue(draft.tracks)
    }

    var totalSeconds: Int { queue.items.compactMap(\.track.durationSeconds).reduce(0, +) }

    static func == (lhs: EditableDraft, rhs: EditableDraft) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
