import SwiftUI

/// The player as one physical object. Collapsed it is the mini player above the tab bar;
/// expanded it is Now Playing. One value, `progress` (0 mini … 1 full), places every piece,
/// so the artwork grows, the glass spreads into the song's background, and the controls
/// arrive, all following the finger or a spring. The audio engine is never involved.
struct PlayerLayer: View {
    @Binding var isExpanded: Bool
    var tabBarHeight: CGFloat
    var open: (PlayerRoute) -> Void
    var askDJ: (String) -> Void

    @Environment(PlayerController.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Vertical drag in points (negative = up).
    @State private var drag: CGFloat = 0
    /// Horizontal drag on the mini player (skip gesture).
    @State private var swipe: CGFloat = 0
    @State private var axis: Axis?
    @State private var palette: ArtworkPalette = .halo
    @State private var showingQueue = false

    var body: some View {
        if let item = player.item {
            // Read the safe area here (inside it, the insets are real), then draw the player
            // over the whole screen, edge to edge.
            GeometryReader { proxy in
                let insets = proxy.safeAreaInsets
                let screen = CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                                    height: proxy.size.height + insets.top + insets.bottom)
                let geometry = PlayerGeometry(
                    size: screen, insets: insets, tabBarHeight: tabBarHeight,
                    accessibilitySize: typeSize.isAccessibilitySize)
                content(item, geometry)
                    .frame(width: screen.width, height: screen.height, alignment: .topLeading)
                    .offset(x: -insets.leading, y: -insets.top)
            }
            .ignoresSafeArea(.keyboard)
            .task(id: item.largeArtworkURL) { await loadPalette(item) }
            .sheet(isPresented: $showingQueue) { QueueView() }
            .onChange(of: isExpanded) { _, expanded in player.setDetailedProgress(expanded) }
        }
    }

    // MARK: Layout

    private func progress(_ geometry: PlayerGeometry) -> CGFloat {
        min(max((isExpanded ? 1 : 0) - drag / geometry.travel, 0), 1)
    }

    @ViewBuilder
    private func content(_ item: NowPlayingItem, _ geometry: PlayerGeometry) -> some View {
        let p = progress(geometry)
        // With Reduce Motion nothing moves: the two states crossfade.
        let shape = reduceMotion ? (p > 0.5 ? 1 : 0) : p
        let surface = PlayerMath.lerp(geometry.mini, geometry.full, shape)
        let art = PlayerMath.lerp(geometry.miniArt, geometry.fullArt, shape)
        let corner = shape >= 0.999 ? 0 : PlayerMath.lerp(PlayerGeometry.miniCorner, 40, shape)
        let artCorner = PlayerMath.lerp(Radius.small, 20, shape)
        let ambient = PlayerMath.window(p, 0.15, 0.8)
        let controls = PlayerMath.window(p, 0.55, 1)
        let paused = isExpanded && drag == 0 && !player.phase.wantsToPlay

        ZStack(alignment: .topLeading) {
            // Glass in the mini player, the song's own environment when expanded.
            Color.clear
                .frame(width: surface.width, height: surface.height)
                .overlay {
                    if ambient > 0 {
                        AmbientBackground(palette: palette, artworkURL: item.largeArtworkURL)
                            .opacity(ambient)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .background {
                    Color.clear.haloGlass(cornerRadius: corner, tint: palette.color(\.glow))
                        .opacity(1 - ambient)
                }
                // Interaction is attached before `.position`: a positioned view fills its
                // container, so anything added after it would cover the whole screen.
                .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .onTapGesture { if !isExpanded { expand() } }
                .position(x: surface.midX, y: surface.midY)

            MiniPlayerContent(item: item, swipe: swipe)
                .frame(width: geometry.mini.width, height: geometry.mini.height)
                .contentShape(Rectangle())
                .onTapGesture { expand() }
                .opacity(1 - PlayerMath.window(p, 0, 0.25))
                .allowsHitTesting(p < 0.05)
                .accessibilityHidden(p > 0.5)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("miniPlayer")
                .accessibilityAction(named: "Open Now Playing") { expand() }
                .accessibilityAction(.magicTap) { player.togglePlayPause() }
                .position(x: surface.minX + geometry.mini.width / 2,
                          y: surface.minY + geometry.mini.height / 2)

            HaloArtwork(url: item.largeArtworkURL ?? item.artworkURL, size: nil,
                        cornerRadius: artCorner, maxPointSize: ArtworkPoints.nowPlaying)
                .frame(width: art.width, height: art.height)
                .overlay { HaloRing(active: player.phase.isWaiting && p > 0.6, cornerRadius: artCorner) }
                .shadow(color: .black.opacity(0.35 * ambient), radius: 30, y: 16)
                .scaleEffect(paused && !reduceMotion ? 0.96 : 1)
                .animation(HaloMotion.emphasized, value: paused)
                .onTapGesture { if !isExpanded { expand() } }
                .position(x: art.midX, y: art.midY)

            if p > 0.01 {
                NowPlayingView(
                    item: item, geometry: geometry, palette: palette,
                    collapse: collapse, openQueue: { showingQueue = true },
                    askDJ: { prompt in
                        collapse()
                        askDJ(prompt)
                    },
                    open: { route in
                        collapse()
                        open(route)
                    })
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .offset(y: (1 - controls) * 14 + max(drag, 0) * 0.15)
                    .opacity(controls)
                    .allowsHitTesting(p > 0.95)
                    .accessibilityHidden(p < 0.5)
                    .accessibilityAction(.escape) { collapse() }
                    .accessibilityAction(.magicTap) { player.togglePlayPause() }
            }
        }
        .gesture(dragGesture(geometry), including: allowsDrag ? .all : .subviews)
    }

    /// At accessibility text sizes Now Playing scrolls, so it closes with the chevron instead.
    private var allowsDrag: Bool { !(isExpanded && typeSize.isAccessibilitySize) }

    // MARK: Gestures

    private func dragGesture(_ geometry: PlayerGeometry) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if axis == nil {
                    let horizontal = abs(value.translation.width) > abs(value.translation.height)
                    axis = (!isExpanded && horizontal && player.canSkip) ? .horizontal : .vertical
                }
                if axis == .horizontal {
                    swipe = value.translation.width
                } else {
                    drag = isExpanded ? max(value.translation.height, 0) : min(value.translation.height, 0)
                }
            }
            .onEnded { value in
                defer { axis = nil }
                if axis == .horizontal {
                    finishSwipe(value.translation.width)
                    return
                }
                let travel = geometry.travel
                let moved = value.translation.height
                let predicted = value.predictedEndTranslation.height
                if isExpanded {
                    let close = moved > travel * 0.3 || predicted > travel * 0.6
                    settle(expanded: !close)
                } else {
                    let open = -moved > travel * 0.15 || -predicted > travel * 0.4
                    settle(expanded: open)
                }
            }
    }

    private func finishSwipe(_ width: CGFloat) {
        if width < -60, player.hasNext {
            Haptics.tap(enabled: settings.hapticsEnabled)
            player.next()
        } else if width > 60 {
            Haptics.tap(enabled: settings.hapticsEnabled)
            player.previous()
        }
        withAnimation(HaloMotion.standard) { swipe = 0 }
    }

    private func expand() { settle(expanded: true) }

    private func collapse() { settle(expanded: false) }

    private func settle(expanded: Bool) {
        if expanded != isExpanded { Haptics.tap(enabled: settings.hapticsEnabled) }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : HaloMotion.player) {
            isExpanded = expanded
            drag = 0
        }
    }

    private func loadPalette(_ item: NowPlayingItem) async {
        let fallback = ArtworkPalette.fallback(seed: item.subtitle)
        guard let url = item.largeArtworkURL ?? item.artworkURL else {
            palette = fallback
            return
        }
        let found = await ArtworkPipeline.shared.palette(for: url)
        guard !Task.isCancelled else { return }
        palette = found ?? fallback
    }
}
