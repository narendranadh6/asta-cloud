import SwiftData
import SwiftUI

/// Screen 10 — Browser handoff: destination, detection status and explicit limits.
struct BrowserHandoffView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(HandoffController.self) private var handoff
    @Query(filter: #Predicate<TrackEntity> { $0.isSaved && $0.isAvailable },
           sort: \TrackEntity.savedAt, order: .reverse)
    private var saved: [TrackEntity]

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                Picker("Open YouTube links in", selection: $settings.browserPreference) {
                    ForEach(BrowserDestination.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Brave on this iPhone",
                               value: app.handoff.canOpenBrave() ? "Detected" : "Not detected")
                LabeledContent("Current destination", value: app.handoff.destinationDescription())
            } footer: {
                Text("MUSE opens Brave with its public link format brave://open-url?url=… and "
                     + "falls back to a normal https:// YouTube link. If the YouTube app is "
                     + "installed, iOS may open https links there instead of a browser.")
            }

            Section("Test") {
                if let track = saved.first(where: { !$0.isDemo }) {
                    Button {
                        Task { await handoff.open(track, using: app.handoff, haptics: settings.hapticsEnabled) }
                    } label: {
                        Label("Open “\(track.title)”", systemImage: "arrow.up.forward.app")
                    }
                    if let result = handoff.lastResult {
                        LabeledContent("Last handoff", value: result.openedWith == .brave
                                       ? "Brave" : (result.usedFallback ? "HTTPS fallback" : "Default browser"))
                    }
                } else {
                    Text("Save a real YouTube song to test the handoff with it.")
                        .foregroundStyle(MUSEColor.mutedText)
                }
            }

            Section("What MUSE can't do") {
                ForEach(Self.limitations, id: \.self) { text in
                    Label(text, systemImage: "xmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(MUSEColor.mutedText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .museScreen()
        .navigationTitle("Browser handoff")
    }

    static let limitations = [
        "Control play or pause in Brave",
        "See Brave's queue, history or playback progress",
        "Automatically play the next song in a MUSE playlist",
        "Guarantee background playback",
        "Block or change YouTube ads",
        "Download or extract audio",
    ]
}
