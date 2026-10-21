import SwiftUI

enum AppTab: Hashable {
    case home, search, dj, library, settings
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PlayerController.self) private var player
    @State private var selection: AppTab = .home
    @State private var playerExpanded = false
    @State private var tabBarHeight: CGFloat = 60
    @State private var toast: String?

    var body: some View {
        Group {
            if settings.hasCompletedOnboarding {
                tabs
            } else {
                OnboardingView()
            }
        }
        .task { await app.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            // Keep the queue and position in case iOS closes Halo in the background.
            if phase == .background { player.saveSession() }
            if phase == .active, settings.syncPlaylists {
                Task { await app.sync.syncPending() }
            }
        }
        .onChange(of: app.network.isOnline) { _, online in
            if online, settings.syncPlaylists {
                Task { await app.sync.syncPending() }
            }
        }
        .onChange(of: player.item == nil) { _, gone in if gone { playerExpanded = false } }
        .onChange(of: player.skippedCount) { _, count in
            guard count > 0 else { return }
            toast = count == 1 ? "Skipped a song that couldn't play"
                : "Skipped \(count) songs that couldn't play"
            player.acknowledgeSkips()
        }
    }

    private var tabs: some View {
        ZStack {
            VStack(spacing: 0) {
                TabView(selection: $selection) {
                    tab(.home) { HomeView(selectTab: { selection = $0 }) }
                    tab(.search) { SearchView() }
                    tab(.dj) { AIDJView() }
                    tab(.library) { LibraryView() }
                    tab(.settings) { SettingsView() }
                }
                // Room for the floating mini player so it never covers the last row.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if player.item != nil {
                        Color.clear.frame(height: PlayerGeometry.miniHeight + Spacing.sm)
                    }
                }
                HaloTabBar(selection: $selection)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabBarHeight = $0 }
            }
            .accessibilityHidden(playerExpanded)
            PlayerLayer(isExpanded: $playerExpanded, tabBarHeight: tabBarHeight) { prompt in
                app.pendingDJPrompt = prompt
                selection = .dj
            }
        }
        .haloToast($toast, edge: .bottom, padding: tabBarHeight + PlayerGeometry.miniHeight + Spacing.lg)
        .background(HaloColor.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            if !app.network.isOnline {
                Label("Offline — saved music still works", systemImage: "wifi.slash")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(Capsule().fill(HaloColor.surface))
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
struct HaloTabBar: View {
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
                        .foregroundStyle(selection == .dj ? HaloColor.text : HaloColor.mutedText)
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
                .overlay(HaloColor.background.opacity(0.65))
                .overlay(alignment: .top) { Divider().overlay(HaloColor.primary.opacity(0.3)) }
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
            .foregroundStyle(selection == tab ? HaloColor.primary : HaloColor.mutedText)
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
    }

    private func select(_ tab: AppTab) {
        if selection != tab { Haptics.tap(enabled: settings.hapticsEnabled) }
        selection = tab
    }
}
