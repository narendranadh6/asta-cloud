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
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeView(selectTab: { selection = $0 }) }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            NavigationStack { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
            NavigationStack { AIDJView() }
                .tabItem { Label("AI DJ", systemImage: "sparkles") }
                .tag(AppTab.dj)
            NavigationStack { LibraryView() }
                .tabItem { Label("Library", systemImage: "music.note.list") }
                .tag(AppTab.library)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .overlay(alignment: .top) {
            if !app.network.isOnline {
                Label("Offline — saved music still works", systemImage: "wifi.slash")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(Capsule().fill(MUSEColor.surface))
                    .padding(.top, Spacing.xs)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }
}

/// Shared handoff entry point so every screen reports results and errors the same way.
@MainActor
@Observable
final class HandoffController {
    var lastError: Error?
    var lastResult: HandoffResult?
    var isOpening = false

    func open(_ track: any TrackDisplayable, using service: BraveBrowserHandoffService,
              haptics: Bool) async {
        guard !track.isDemo else {
            lastError = HandoffError.demoContent
            Haptics.warning(enabled: haptics)
            return
        }
        await run(haptics: haptics) { try await service.openYouTubeVideo(id: track.videoId) }
    }

    func openPlaylist(id: String, using service: BraveBrowserHandoffService, haptics: Bool) async {
        await run(haptics: haptics) { try await service.openYouTubePlaylist(id: id) }
    }

    private func run(haptics: Bool, _ action: () async throws -> HandoffResult) async {
        isOpening = true
        defer { isOpening = false }
        do {
            lastResult = try await action()
            Haptics.tap(enabled: haptics)
        } catch {
            lastError = error
            Haptics.warning(enabled: haptics)
        }
    }
}
