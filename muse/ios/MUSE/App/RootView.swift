import SwiftUI

enum AppTab: Hashable {
    case home, search, dj, library, settings
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .home
    @State private var handoff = HandoffController()
    @State private var showingNowInBrave = false

    var body: some View {
        Group {
            if settings.hasCompletedOnboarding {
                tabs
            } else {
                OnboardingView()
            }
        }
        .environment(handoff)
        .task { await app.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, settings.syncPlaylists {
                Task { await app.sync.syncPending() }
            }
        }
        .onChange(of: app.network.isOnline) { _, online in
            if online, settings.syncPlaylists {
                Task { await app.sync.syncPending() }
            }
        }
        .alert(
            "Couldn't open link",
            isPresented: Binding(
                get: { handoff.lastError != nil }, set: { if !$0 { handoff.lastError = nil } }),
            presenting: handoff.lastError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .sheet(isPresented: $showingNowInBrave) {
            NowInBraveView(selectTab: { tab in
                showingNowInBrave = false
                selection = tab
            })
            .environment(handoff)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var tabs: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                tab(.home) { HomeView(selectTab: { selection = $0 }) }
                tab(.search) { SearchView() }
                tab(.dj) { AIDJView() }
                tab(.library) { LibraryView() }
                tab(.settings) { SettingsView() }
            }
            if let context = handoff.nowInBrave {
                NowInBraveMiniBar(context: context) { showingNowInBrave = true }
            }
            MUSETabBar(selection: $selection)
        }
        .background(MUSEColor.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            if !app.network.isOnline {
                Label("Offline — saved music still works", systemImage: "wifi.slash")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(Capsule().fill(MUSEColor.surface))
                    .padding(.top, Spacing.xs)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func tab<Content: View>(_ tag: AppTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack { content() }
            .toolbar(.hidden, for: .tabBar)
            .tag(tag)
    }
}

/// Custom tab bar with the AI DJ orb in the centre (mockup style).
struct MUSETabBar: View {
    @Binding var selection: AppTab
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            item(.home, "Home", "house.fill")
            item(.search, "Search", "magnifyingglass")
            Button {
                select(.dj)
            } label: {
                VStack(spacing: 2) {
                    AIOrb(size: 50, isActive: selection == .dj)
                    Text("AI DJ").font(.caption2.weight(.semibold))
                        .foregroundStyle(selection == .dj ? MUSEColor.text : MUSEColor.mutedText)
                }
                .offset(y: -6)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("AI DJ")
            .accessibilityAddTraits(selection == .dj ? [.isSelected] : [])
            item(.library, "Library", "books.vertical.fill")
            item(.settings, "Profile", "person.crop.circle")
        }
        .padding(.top, Spacing.xs)
        .padding(.horizontal, Spacing.xs)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(MUSEColor.background.opacity(0.65))
                .overlay(alignment: .top) { Divider().overlay(MUSEColor.primary.opacity(0.3)) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(_ tab: AppTab, _ title: String, _ symbol: String) -> some View {
        Button {
            select(tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                Text(title).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selection == tab ? MUSEColor.primary : MUSEColor.mutedText)
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
    }

    private func select(_ tab: AppTab) {
        if selection != tab { Haptics.tap(enabled: settings.hapticsEnabled) }
        selection = tab
    }
}

/// What MUSE knows after a handoff: which song it opened and what could come next.
/// It deliberately has no playback state — MUSE can't see inside Brave.
struct NowInBraveContext: Equatable {
    var track: Track
    var upNext: [Track]
    var openedAt: Date
    var openedWith: HandoffResult.Opener
}

/// Shared handoff entry point so every screen reports results and errors the same way.
@MainActor
@Observable
final class HandoffController {
    var lastError: Error?
    var lastResult: HandoffResult?
    var isOpening = false
    private(set) var nowInBrave: NowInBraveContext?

    /// Opens a track. `upNext` is the rest of the list it came from, so the user can pick
    /// the next song themselves — MUSE can't auto-advance in Brave.
    func open(_ track: any TrackDisplayable, upNext: [any TrackDisplayable] = [],
              using service: BraveBrowserHandoffService, haptics: Bool) async {
        guard let result = await run(haptics: haptics, {
            try await service.openYouTubeVideo(id: track.videoId)
        }) else { return }
        nowInBrave = NowInBraveContext(
            track: Self.track(from: track),
            upNext: upNext.filter { $0.videoId != track.videoId }.prefix(20)
                .map(Self.track(from:)),
            openedAt: .now,
            openedWith: result.openedWith)
    }

    func openPlaylist(id: String, using service: BraveBrowserHandoffService, haptics: Bool) async {
        _ = await run(haptics: haptics) { try await service.openYouTubePlaylist(id: id) }
    }

    /// Opens the chosen "up next" song and keeps the remainder of the list.
    func openNext(_ track: Track, using service: BraveBrowserHandoffService, haptics: Bool) async {
        let remaining = nowInBrave?.upNext.filter { $0.videoId != track.videoId } ?? []
        await open(track, upNext: remaining, using: service, haptics: haptics)
    }

    func clearNowInBrave() {
        nowInBrave = nil
    }

    private func run(haptics: Bool, _ action: () async throws -> HandoffResult) async
        -> HandoffResult?
    {
        isOpening = true
        defer { isOpening = false }
        do {
            let result = try await action()
            lastResult = result
            Haptics.tap(enabled: haptics)
            return result
        } catch {
            lastError = error
            Haptics.warning(enabled: haptics)
            return nil
        }
    }

    private static func track(from item: any TrackDisplayable) -> Track {
        if let track = item as? Track { return track }
        return Track(reference: item, provider: .youtube)
    }
}
