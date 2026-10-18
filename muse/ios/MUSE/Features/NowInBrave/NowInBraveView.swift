import SwiftData
import SwiftUI

/// Mini bar above the tab bar after a handoff. Shows what MUSE opened — not what is
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
                        .foregroundStyle(MUSEColor.text).lineLimit(1)
                    Text("Opened in \(context.openedWith == .brave ? "Brave" : "your browser") · "
                         + context.track.channelTitle)
                        .font(.caption).foregroundStyle(MUSEColor.mutedText).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up").foregroundStyle(MUSEColor.mutedText)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .museCard(cornerRadius: Spacing.corner)
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, Spacing.xxs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Last opened in browser: \(context.track.title). Show details")
    }
}

/// The mockup's "Now Playing" screen, made honest: artwork and details of the song MUSE
/// handed off, a way to reopen it, and an up-next list the user advances manually.
/// There is no play/pause, seek bar or progress because MUSE cannot see or control Brave.
struct NowInBraveView: View {
    var selectTab: (AppTab) -> Void

    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(HandoffController.self) private var handoff
    @Environment(\.dismiss) private var dismiss
    @State private var isSaved = false

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
            .museScreen()
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
                    Text("OPENED FROM MUSE").font(.caption2.weight(.semibold))
                        .foregroundStyle(MUSEColor.mutedText)
                    Label(context.openedWith == .brave ? "Playing in Brave" : "Opened in your browser",
                          systemImage: "play.rectangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MUSEColor.text)
                }
                ArtworkView(url: context.track.artworkURL, size: nil, cornerRadius: Spacing.cornerLarge)
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: MUSEColor.secondary.opacity(0.45), radius: 30, y: 14)
                    .padding(.horizontal, Spacing.md)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.track.title).font(MUSEFont.title).foregroundStyle(MUSEColor.text)
                        Text(context.track.channelTitle).font(.headline).foregroundStyle(MUSEColor.mutedText)
                        Text("Opened \(context.openedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(MUSEColor.mutedText)
                    }
                    Spacer()
                    Button {
                        isSaved.toggle()
                        app.library.setSaved(isSaved, track: context.track)
                        Haptics.tap(enabled: settings.hapticsEnabled)
                    } label: {
                        Image(systemName: isSaved ? "heart.fill" : "heart").font(.title2)
                            .foregroundStyle(isSaved ? MUSEColor.secondary : MUSEColor.text)
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
                        + ". MUSE can't see or control them, so pick the next song below when you're ready.",
                    systemImage: "hand.raised")

                if !context.upNext.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        SectionHeader(title: "Up next — you choose")
                        ForEach(context.upNext.prefix(8)) { track in
                            Button {
                                Task { await handoff.openNext(track, using: app.handoff, haptics: settings.hapticsEnabled) }
                            } label: {
                                HStack {
                                    TrackRow(track: track, showsAttribution: false)
                                    Image(systemName: "arrow.up.forward.app").foregroundStyle(MUSEColor.accent)
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
                            Text("Ask MUSE…").font(.headline).foregroundStyle(MUSEColor.text)
                            Text("Find songs similar to “\(context.track.title)”")
                                .font(.caption).foregroundStyle(MUSEColor.mutedText)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill").font(.title2).foregroundStyle(MUSEColor.primary)
                    }
                    .padding(Spacing.sm)
                    .museCard()
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.md)
        }
        .museDestinations()
        .task { isSaved = app.library.isSaved(videoId: context.track.videoId) }
    }
}
