import AVKit
import SwiftData
import SwiftUI

/// Full-screen player. Every control acts on the real AVPlayer through `PlayerController`.
struct NowPlayingView: View {
    var selectTab: (AppTab) -> Void

    @Environment(AppModel.self) private var app
    @Environment(PlayerController.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query(sort: \PlaylistEntity.updatedAt, order: .reverse) private var playlists: [PlaylistEntity]

    @State private var scrubbing: Double?
    @State private var showingQueue = false
    @State private var isSaved = false
    @State private var confirmation: String?

    var body: some View {
        ZStack {
            background
            if let item = player.item {
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        artwork(item)
                        titleBlock(item)
                        if !item.isLive { scrubber }
                        transport(item)
                        actions(item)
                        if let track = item.track { sourceNote(track) }
                        if let issue = player.phase.issue {
                            NoticeBanner(text: "\(issue.title). \(issue.message)",
                                         systemImage: "exclamationmark.triangle")
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.xl)
                    .padding(.bottom, Spacing.xxl)
                }
            } else {
                EmptyStateView(
                    title: "Nothing playing", message: "Pick a song or a station to start listening.",
                    systemImage: "music.note", actionTitle: "Close", action: { dismiss() })
            }
        }
        .sheet(isPresented: $showingQueue) { QueueView() }
        .onAppear(perform: refreshSaved)
        .onChange(of: player.currentTrack?.id) { _, _ in refreshSaved() }
        .overlay(alignment: .bottom) {
            if let confirmation {
                Text(confirmation)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
                    .background(Capsule().fill(Surface.overlay))
                    .padding(.bottom, Spacing.lg)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        self.confirmation = nil
                    }
            }
        }
    }

    // MARK: Pieces

    private var background: some View {
        ZStack {
            HaloColor.background
            if let url = player.item?.artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill().blur(radius: 60).opacity(0.45)
                } placeholder: { Color.clear }
            }
            LinearGradient(colors: [.clear, HaloColor.background], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func artwork(_ item: NowPlayingItem) -> some View {
        HaloArtwork(url: item.largeArtworkURL, size: nil, cornerRadius: Radius.large)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 340)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .strokeBorder(HaloColor.neon, lineWidth: player.phase == .playing ? 2 : 0)
            }
            .shadow(color: HaloColor.primary.opacity(player.phase == .playing ? 0.55 : 0.2),
                    radius: 32, y: 14)
            .scaleEffect(player.phase == .playing ? 1 : 0.92)
            .animation(HaloMotion.emphasized, value: player.phase)
    }

    private func titleBlock(_ item: NowPlayingItem) -> some View {
        VStack(spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                if item.isLive {
                    Text("LIVE").font(HaloFont.eyebrow)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(HaloColor.secondary))
                } else if let track = item.track {
                    SourceBadge(isPreview: track.isPreview, source: track.source)
                }
            }
            Text(item.title).font(HaloFont.title).foregroundStyle(HaloColor.text)
                .multilineTextAlignment(.center).lineLimit(2)
            Text(item.subtitle).font(.headline).foregroundStyle(HaloColor.mutedText)
                .lineLimit(1)
            if let album = item.track?.album {
                Text(album).font(.subheadline).foregroundStyle(HaloColor.mutedText).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var scrubber: some View {
        let duration = max(player.clock.duration ?? 0, 1)
        let shown = scrubbing ?? player.clock.position
        return VStack(spacing: 4) {
            Slider(
                value: Binding(get: { min(shown, duration) }, set: { scrubbing = $0 }),
                in: 0...duration,
                onEditingChanged: { editing in
                    if !editing, let target = scrubbing {
                        player.seek(to: target)
                        scrubbing = nil
                    }
                })
            .tint(HaloColor.primary)
            .accessibilityLabel("Position")
            .accessibilityValue("\(DurationFormatter.clock(Int(shown))) of \(DurationFormatter.clock(Int(duration)))")
            HStack {
                Text(DurationFormatter.clock(Int(shown)))
                Spacer()
                Text("-" + DurationFormatter.clock(Int(max(duration - shown, 0))))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(HaloColor.mutedText)
        }
    }

    private func transport(_ item: NowPlayingItem) -> some View {
        HStack {
            if !item.isLive {
                Button { player.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .foregroundStyle(player.queue.isShuffled ? HaloColor.primary : HaloColor.mutedText)
                }
                .accessibilityLabel("Shuffle")
                .accessibilityValue(player.queue.isShuffled ? "On" : "Off")
                Spacer()
                Button { player.previous() } label: { Image(systemName: "backward.fill") }
                    .accessibilityLabel("Previous")
                Spacer()
            }
            Button {
                Haptics.tap(enabled: settings.hapticsEnabled)
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(HaloColor.neon).frame(width: 76, height: 76)
                        .shadow(color: HaloColor.primary.opacity(0.5), radius: 16, y: 6)
                    if player.phase.isWaiting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: playSymbol(item)).font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .accessibilityLabel(player.isPlaying ? (item.isLive ? "Stop" : "Pause") : "Play")
            if !item.isLive {
                Spacer()
                Button { player.next() } label: { Image(systemName: "forward.fill") }
                    .disabled(!player.hasNext)
                    .accessibilityLabel("Next")
                Spacer()
                Button { player.cycleRepeat() } label: {
                    Image(systemName: player.queue.repeatMode == .one ? "repeat.1" : "repeat")
                        .foregroundStyle(player.queue.repeatMode == .off ? HaloColor.mutedText : HaloColor.primary)
                }
                .accessibilityLabel("Repeat")
                .accessibilityValue(player.queue.repeatMode.rawValue)
            }
        }
        .font(.title2)
        .foregroundStyle(HaloColor.text)
        .frame(maxWidth: .infinity)
    }

    private func playSymbol(_ item: NowPlayingItem) -> String {
        if player.isPlaying { return item.isLive ? "stop.fill" : "pause.fill" }
        return "play.fill"
    }

    private func actions(_ item: NowPlayingItem) -> some View {
        HStack(spacing: Spacing.lg) {
            if let track = item.track {
                Button { toggleSave(track) } label: {
                    Image(systemName: isSaved ? "heart.fill" : "heart")
                        .foregroundStyle(isSaved ? HaloColor.secondary : HaloColor.text)
                }
                .accessibilityLabel(isSaved ? "Remove from saved songs" : "Save song")
                Menu {
                    ForEach(playlists) { playlist in
                        Button(playlist.name) { add(track, to: playlist) }
                    }
                    if playlists.isEmpty {
                        Text("No playlists yet")
                    }
                } label: {
                    Image(systemName: "text.badge.plus")
                }
                .accessibilityLabel("Add to playlist")
                Button {
                    app.pendingDJPrompt = "Songs like \(track.title) by \(track.artist)"
                    selectTab(.dj)
                } label: {
                    Image(systemName: "sparkles")
                }
                .accessibilityLabel("More like this with the AI DJ")
            }
            AirPlayButton().frame(width: 28, height: 28)
                .accessibilityLabel("Play on another device")
            if !item.isLive {
                Button { showingQueue = true } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel("Queue")
            }
        }
        .font(.title3)
        .foregroundStyle(HaloColor.text)
    }

    /// Licence and attribution the sources require, and the path to the full song for previews.
    @ViewBuilder
    private func sourceNote(_ track: Track) -> some View {
        VStack(spacing: Spacing.xs) {
            if track.isPreview {
                Text("This is a 30-second preview. Halo plays full songs from Audius and Jamendo; "
                     + "this one is only available as a preview.")
                    .font(.caption).foregroundStyle(HaloColor.mutedText)
                    .multilineTextAlignment(.center)
                if let url = track.externalURL {
                    Button { openURL(url) } label: {
                        Label("Listen on Apple Music", systemImage: "apple.logo")
                    }
                    .buttonStyle(NeonButtonStyle(prominent: false))
                }
            } else if let license = track.license {
                licenseLine(license, artist: track.artist)
            }
            if let url = track.externalURL, !track.isPreview {
                Link(destination: url) {
                    Text("View on \(track.attribution.label)").font(.caption.weight(.semibold))
                }
                .tint(HaloColor.accent)
            }
        }
    }

    private func licenseLine(_ license: TrackLicense, artist: String) -> some View {
        Group {
            if let url = license.url.flatMap(Track.webURL) {
                Link(destination: url) {
                    Text("“\(player.currentTrack?.title ?? "")” by \(artist) · \(license.name)")
                }
            } else {
                Text("“\(player.currentTrack?.title ?? "")” by \(artist) · \(license.name)")
            }
        }
        .font(.caption)
        .foregroundStyle(HaloColor.mutedText)
        .multilineTextAlignment(.center)
    }

    // MARK: Actions

    private func refreshSaved() {
        isSaved = player.currentTrack.map { app.library.isSaved(trackID: $0.id) } ?? false
    }

    private func toggleSave(_ track: Track) {
        isSaved.toggle()
        app.library.setSaved(isSaved, track: track)
        Haptics.tap(enabled: settings.hapticsEnabled)
        confirmation = isSaved ? "Saved to your library" : "Removed from saved songs"
        guard isSaved, settings.personalizationEnabled else { return }
        Task {
            _ = try? await app.api.sendFeedback(
                FeedbackRequest(trackId: track.id, rating: .save, artist: track.artist))
        }
    }

    private func add(_ track: Track, to playlist: PlaylistEntity) {
        app.library.add(track, to: playlist)
        app.playlistChanged(playlist)
        Haptics.success(enabled: settings.hapticsEnabled)
        confirmation = "Added to \(playlist.name)"
    }
}

/// The queue: tap to jump, drag to reorder, swipe to remove.
struct QueueView: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let current = player.queue.current {
                    Section("Now playing") {
                        TrackRow(track: current.track)
                    }
                }
                Section(player.queue.upNext.isEmpty ? "Up next is empty" : "Up next") {
                    ForEach(player.queue.upNext) { item in
                        Button { player.jump(to: item.id) } label: {
                            TrackRow(track: item.track)
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove { source, destination in
                        // Moves within the whole upcoming list map onto its bands.
                        let upcoming = player.queue.upNext
                        guard let first = source.first, upcoming.indices.contains(first) else { return }
                        let origin = upcoming[first].origin
                        let band = upcoming.filter { $0.origin == origin }
                        let from = IndexSet(source.compactMap { index in
                            band.firstIndex { $0.id == upcoming[index].id } })
                        let target = upcoming.prefix(destination).filter { $0.origin == origin }.count
                        player.move(in: origin, from: from, to: target)
                    }
                    .onDelete { offsets in
                        let upcoming = player.queue.upNext
                        for offset in offsets where upcoming.indices.contains(offset) {
                            player.removeFromQueue(upcoming[offset].id)
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(HaloColor.background)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// System AirPlay / Bluetooth output picker.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(HaloColor.primary)
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
