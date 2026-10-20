import Foundation
import Observation

@MainActor
@Observable
final class PlaylistStudioViewModel {
    var description = ""
    var mood: Mood?
    var genresText = ""
    var language = ""
    var energy: Double = 50
    var useEnergy = false
    var durationMinutes = 60
    var discovery: DiscoveryPreference = .balanced

    var draft: EditableDraft?
    private(set) var isGenerating = false
    private(set) var error: Error?

    static let languages = ["", "Telugu", "Hindi", "Tamil", "Malayalam", "Kannada", "Punjabi",
                            "Bengali", "English", "Spanish", "Korean", "Japanese", "French"]

    var canGenerate: Bool {
        description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 && !isGenerating
    }

    func request(excluding: [String] = []) -> AIPlaylistRequest {
        let genres = genresText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return AIPlaylistRequest(
            description: String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)),
            mood: mood,
            genres: Array(genres.prefix(5)),
            language: language.isEmpty ? nil : language,
            energy: useEnergy ? Int(energy) : nil,
            durationMinutes: min(max(durationMinutes, 10), 300),
            discovery: discovery,
            excludeTrackIds: Array(excluding.prefix(200)))
    }

    func generate(api: MusicAPI) async {
        await run(api: api, request: request())
    }

    /// New picks, excluding songs the user removed and the ones already shown.
    func regenerate(api: MusicAPI, shownIDs: [String]) async {
        await run(api: api, request: request(excluding: shownIDs))
    }

    private func run(api: MusicAPI, request: AIPlaylistRequest) async {
        isGenerating = true
        error = nil
        defer { isGenerating = false }
        do {
            let result = try await api.aiPlaylist(request)
            let keepTitle = draft?.title
            var editable = EditableDraft(result)
            if let keepTitle, !keepTitle.isEmpty { editable.title = keepTitle }
            draft = editable
        } catch {
            self.error = error
        }
    }
}
