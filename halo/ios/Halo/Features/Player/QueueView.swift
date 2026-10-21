import SwiftUI

/// What plays next, and why: your additions first, then what you started from, then Halo Flow.
/// Drag to reorder within a section, swipe left to remove, swipe right to play next.
struct QueueView: View {
    @Environment(PlayerController.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var showsHistory = false

    var body: some View {
        NavigationStack {
            List {
                if let current = player.queue.current {
                    Section {
                        row(current, showsHandle: false)
                    } header: {
                        Text("Now playing")
                    }
                }
                band(.user, title: "Next in queue", footer: "Songs you added play before everything else.") {
                    Button("Clear") { player.clearUserQueue() }
                        .font(.footnote.weight(.semibold))
                }
                band(.context, title: contextTitle, footer: nil)
                if player.currentTrack != nil { flowSection }
                if !player.queue.history.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showsHistory) {
                            ForEach(player.queue.history.reversed()) { item in
                                Button { player.jump(to: item.id) } label: { row(item, showsHandle: false) }
                                    .buttonStyle(.plain)
                            }
                        } label: {
                            Text("Recently played").font(.subheadline.weight(.semibold))
                        }
                        .tint(HaloColor.mutedText)
                    }
                }
                if player.queue.upNext.isEmpty {
                    Section {
                        Text("Nothing is queued. Add songs with Play Next or Add to Queue.")
                            .font(.footnote)
                            .foregroundStyle(HaloColor.mutedText)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.thinMaterial)
        .presentationCornerRadius(Radius.large)
    }

    /// Halo Flow: always visible for songs, so Autoplay can be switched from here.
    private var flowSection: some View {
        @Bindable var settings = settings
        let items = player.queue.upNext(.flow)
        return Section {
            if settings.autoplay {
                ForEach(items) { item in
                    Button { player.jump(to: item.id) } label: { row(item, showsHandle: true) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button { player.moveToNext(item.id) } label: {
                                Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
                            }
                            .tint(HaloColor.accent)
                        }
                }
                .onMove { player.move(in: .flow, from: $0, to: $1) }
                .onDelete { offsets in
                    for offset in offsets where items.indices.contains(offset) {
                        player.removeFromQueue(items[offset].id)
                    }
                }
                if player.isLoadingFlow {
                    Label("Finding songs to follow…", systemImage: "sparkles")
                        .font(.footnote).foregroundStyle(HaloColor.mutedText)
                } else if items.isEmpty {
                    Text("Halo Flow picks songs when your queue is nearly done.")
                        .font(.footnote).foregroundStyle(HaloColor.mutedText)
                }
            }
        } header: {
            HStack {
                Text("Halo Flow")
                Spacer()
                if settings.autoplay && !items.isEmpty {
                    Button("Refresh") { player.refreshFlow() }
                        .font(.footnote.weight(.semibold))
                        .accessibilityHint("Replaces the suggestions with new ones")
                }
                Toggle("Autoplay", isOn: $settings.autoplay)
                    .labelsHidden()
                    .controlSize(.mini)
                    .accessibilityLabel("Autoplay with Halo Flow")
            }
        } footer: {
            Text(settings.autoplay
                 ? "Plays after your songs, never instead of them."
                 : "Autoplay is off: music stops when the queue ends.")
        }
    }

    private var contextTitle: String {
        player.queue.contextTitle.map { "Next from \($0)" } ?? "Next up"
    }

    @ViewBuilder
    private func band<Trailing: View>(
        _ origin: PlaybackQueue.Origin, title: String, footer: String?,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        let items = player.queue.upNext(origin)
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    Button { player.jump(to: item.id) } label: { row(item, showsHandle: true) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            if origin != .user {
                                Button { player.moveToNext(item.id) } label: {
                                    Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
                                }
                                .tint(HaloColor.accent)
                            }
                        }
                }
                .onMove { player.move(in: origin, from: $0, to: $1) }
                .onDelete { offsets in
                    for offset in offsets where items.indices.contains(offset) {
                        player.removeFromQueue(items[offset].id)
                    }
                }
            } header: {
                HStack {
                    Text(title)
                    Spacer()
                    trailing()
                }
            } footer: {
                if let footer { Text(footer) }
            }
        }
    }

    private func row(_ item: PlaybackQueue.Item, showsHandle: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            HaloArtwork(url: item.track.artworkURL, size: 44, cornerRadius: Radius.small)
                .overlay(alignment: .leading) {
                    if item.origin == .user {
                        // Songs the listener added carry a cyan edge.
                        Capsule().fill(HaloColor.accent).frame(width: 3).padding(.vertical, 6)
                            .offset(x: -6)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.track.artist).lineLimit(1)
                    if let reason = item.reason {
                        Text(reason)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(HaloColor.accent.opacity(0.18)))
                            .foregroundStyle(HaloColor.accent)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(HaloColor.mutedText)
            }
            Spacer(minLength: 0)
        }
        .opacity(item.origin == .flow ? 0.72 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(hint(item.origin))
    }

    private func hint(_ origin: PlaybackQueue.Origin) -> String {
        switch origin {
        case .user: "Added by you"
        case .context: "From \(player.queue.contextTitle ?? "this list")"
        case .flow: "Suggested by Halo Flow"
        }
    }
}
