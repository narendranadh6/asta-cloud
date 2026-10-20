import SwiftData
import SwiftUI

/// Mini bar above the tab bar after a handoff. Shows what Halo opened — not what is
/// playing — and reopens the Now in Brave screen.
struct NowInBraveMiniBar: View {
    var context: NowInBraveContext
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                ArtworkView(url: context.track.artworkURL, size: 42, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.track.title).font(.subheadline.weight(.semibold))
                        .foregroundStyle(HaloColor.text).lineLimit(1)
                    Text("Opened in \(context.openedWith == .brave ? "Brave" : "your browser") · "
                         + context.track.channelTitle)
                        .font(.caption).foregroundStyle(HaloColor.mutedText).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up").foregroundStyle(HaloColor.mutedText)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .haloCard(cornerRadius: Spacing.corner)
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, Spacing.xxs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Last opened in browser: \(context.track.title). Show details")
    }
}

/// The mockup's "Now Playing" screen, made honest: artwork and details of the song Halo
/// handed off, a way to reopen it, and an up-next list the user advances manually.
/// There is no play/pause, seek bar or progress because Halo cannot see or control Brave.
struct NowInBraveView: View {
    var selectTab: (AppTab) -> Void

    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(HandoffController.self) private var handoff
    @Environment(\.dismiss) private var dismiss
    @State private var isSaved = false
    @State private var suggested: [RecommendedTrack] = []

    var body: some View {
        NavigationStack {
            Group {
                if let context = handoff.nowInBrave {
                    content(context)
                } else {
                    ContentUnavailableView("Nothing opened yet", systemImage: "arrow.up.forward.app",
                                           description: Text("Pick a song and tap Listen in Brave."))
                }
            }
            .haloScreen()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "chevron.down") { dismiss() }
                }
            }
        }
    }

    private func content(_ context: NowInBraveContext) -> some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                VStack(spacing: 2) {
                    Text("OPENED FROM Halo").font(.caption2.weight(.semibold))
                        .foregroundStyle(HaloColor.mutedText)
                    Label(context.openedWith == .brave ? "Playing in Brave" : "Opened in your browser",
                          systemImage: "play.rectangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HaloColor.text)
                }
                ArtworkView(url: context.track.artworkURL, size: nil, cornerRadius: Spacing.cornerLarge)
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: HaloColor.secondary.opacity(0.45), radius: 30, y: 14)
                    .padding(.horizontal, Spacing.md)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.track.title).font(HaloFont.title).foregroundStyle(HaloColor.text)
                        Text(context.track.channelTitle).font(.headline).foregroundStyle(HaloColor.mutedText)
                        Text("Opened \(context.openedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(HaloColor.mutedText)
                    }
                    Spacer()
                    Button {
                        isSaved.toggle()
                        app.library.setSaved(isSaved, track: context.track)
                        Haptics.tap(enabled: settings.hapticsEnabled)
                    } label: {
                        Image(systemName: isSaved ? "heart.fill" : "heart").font(.title2)
                            .foregroundStyle(isSaved ? HaloColor.secondary : HaloColor.text)
                    }
                    .accessibilityLabel(isSaved ? "Saved" : "Save")
                }

                HStack(spacing: Spacing.sm) {
                    Button {
                        Task {
                            await handoff.open(context.track, upNext: context.upNext,
                                               using: app.handoff, haptics: settings.hapticsEnabled)
                        }
                    } label: {
                        Label("Open again", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeonButtonStyle())
                    NavigationLink(value: context.track) {
                        Label("Details", systemImage: "info.circle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeonButtonStyle(prominent: false))
                }

                NoticeBanner(
                    text: "Play, pause, skip and progress happen in "
                        + (context.openedWith == .brave ? "Brave" : "your browser")
                        + ". Halo can't see or control them, so pick the next song below when you're ready.",
                    systemImage: "hand.raised")

                if context.upNext.isEmpty && !suggested.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        SectionHeader(title: "Up next — picked for you")
                        ForEach(suggested.prefix(8)) { item in
                            Button {
                                Task { await handoff.openNext(item.track, using: app.handoff, haptics: settings.hapticsEnabled) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    TrackRow(track: item.track, showsAttribution: false)
                                    if let reason = item.reasons.first {
                                        Text(reason).font(.caption).foregroundStyle(HaloColor.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !context.upNext.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        SectionHeader(title: "Up next — you choose")
                        ForEach(context.upNext.prefix(8)) { track in
                            Button {
                                Task { await handoff.openNext(track, using: app.handoff, haptics: settings.hapticsEnabled) }
                            } label: {
                                HStack {
                                    TrackRow(track: track, showsAttribution: false)
                                    Image(systemName: "arrow.up.forward.app").foregroundStyle(HaloColor.accent)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens this song in your browser")
                        }
                    }
                }

                Button {
                    app.pendingDJPrompt = "Songs similar to \(context.track.title) by "
                        + "\(context.track.channelTitle), but less popular"
                    selectTab(.dj)
                } label: {
                    HStack {
                        AIOrb(size: 28)
                        VStack(alignment: .leading) {
                            Text("Ask Halo…").font(.headline).foregroundStyle(HaloColor.text)
                            Text("Find songs similar to “\(context.track.title)”")
                                .font(.caption).foregroundStyle(HaloColor.mutedText)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill").font(.title2).foregroundStyle(HaloColor.primary)
                    }
                    .padding(Spacing.sm)
                    .haloCard()
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.md)
        }
        .haloDestinations()
        .task(id: context.track.videoId) {
            isSaved = app.library.isSaved(videoId: context.track.videoId)
            if context.upNext.isEmpty {
                suggested = (try? await app.api.upNext(videoID: context.track.videoId, limit: 8))?.tracks ?? []
            }
        }
    }
}
