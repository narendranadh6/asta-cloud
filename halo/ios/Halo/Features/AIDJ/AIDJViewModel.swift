import Foundation
import Observation

@MainActor
@Observable
final class AIDJViewModel {
    struct Message: Identifiable, Hashable {
        enum Role { case user, assistant, error }
        let id = UUID()
        var role: Role
        var text: String
        var draftIndex: Int?
    }

    var input = ""
    private(set) var messages: [Message] = []
    var drafts: [EditableDraft] = []
    private(set) var isThinking = false
    private var conversationID: UUID?

    static let examples = [
        "Find relaxing Telugu melodies from the 2000s.",
        "Create a late-night coding playlist with minimal vocals.",
        "Recommend songs similar to my favorites but less popular.",
        "Build a playlist for a two-hour road trip.",
    ]

    var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking
    }

    func send(api: MusicAPI) async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        input = ""
        let history = messages.suffix(6).compactMap { message -> ChatTurn? in
            switch message.role {
            case .user: ChatTurn(role: .user, content: String(message.text.prefix(2000)))
            case .assistant: ChatTurn(role: .assistant, content: String(message.text.prefix(2000)))
            case .error: nil
            }
        }
        messages.append(Message(role: .user, text: text))
        isThinking = true
        defer { isThinking = false }
        do {
            let response = try await api.aiChat(AIChatRequest(
                message: String(text.prefix(1000)), conversationId: conversationID,
                history: Array(history)))
            conversationID = response.conversationId ?? conversationID
            var index: Int?
            if let draft = response.draft, !draft.tracks.isEmpty {
                drafts.append(EditableDraft(draft))
                index = drafts.count - 1
            }
            messages.append(Message(role: .assistant, text: response.reply, draftIndex: index))
        } catch {
            messages.append(Message(role: .error, text: error.localizedDescription))
        }
    }

    func reset() {
        messages.removeAll()
        drafts.removeAll()
        conversationID = nil
    }
}
