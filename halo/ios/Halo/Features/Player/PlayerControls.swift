import AVKit
import SwiftUI

/// Drag anywhere on the bar to seek. The track thickens under the finger, the time labels
/// follow it, and the song jumps once on release. The touch area is far taller than the line.
struct ScrubBar: View {
    @Environment(PlayerController.self) private var player
    @Environment(AppSettings.self) private var settings
    @State private var dragFraction: Double?

    var body: some View {
        let clock = player.clock
        let duration = clock.duration ?? 0
        let fraction = dragFraction ?? clock.fraction ?? 0
        let shown = duration * fraction
        let dragging = dragFraction != nil
        VStack(spacing: 2) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let height: CGFloat = dragging ? 10 : 5
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    if let buffered = clock.bufferedFraction {
                        Capsule().fill(.white.opacity(0.18))
                            .frame(width: width * buffered)
                    }
                    Capsule().fill(.white)
                        .frame(width: max(width * fraction, height))
                }
                .frame(height: height)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            if dragFraction == nil { Haptics.tap(enabled: settings.hapticsEnabled) }
                            dragFraction = min(max(value.location.x / width, 0), 1)
                        }
                        .onEnded { value in
                            guard duration > 0 else { return }
                            player.seek(to: min(max(value.location.x / width, 0), 1) * duration)
                            dragFraction = nil
                        })
            }
            .frame(height: 32)
            .animation(HaloMotion.quick, value: dragging)
            HStack {
                Text(DurationFormatter.clock(Int(shown)))
                Spacer()
                Text("-" + DurationFormatter.clock(Int(max(duration - shown, 0))))
            }
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.white.opacity(dragging ? 0.95 : 0.62))
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(spoken(shown)) of \(spoken(duration))")
        .accessibilityAdjustableAction { direction in
            let step: Double = direction == .increment ? 10 : -10
            player.seek(to: clock.position + step)
        }
    }

    private func spoken(_ seconds: Double) -> String {
        let total = Int(seconds)
        let minutes = total / 60, rest = total % 60
        return minutes > 0 ? "\(minutes) minutes \(rest) seconds" : "\(rest) seconds"
    }
}

/// Previous · play/pause · next. Play/pause is the one solid disc on the screen, so it is
/// always the most visible control.
struct TransportControls: View {
    var item: NowPlayingItem
    /// Symbol color on the white disc (the song's base color).
    var ink: Color

    @Environment(PlayerController.self) private var player
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            if !item.isLive {
                skip("backward.fill", label: "Previous") { player.previous() }
                Spacer(minLength: 0)
            }
            Button {
                Haptics.tap(enabled: settings.hapticsEnabled)
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(HaloColor.text)
                    Image(systemName: playSymbol)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(ink)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(player.isPlaying ? (item.isLive ? "Stop" : "Pause") : "Play")
            if !item.isLive {
                Spacer(minLength: 0)
                skip("forward.fill", label: "Next") { player.next() }
                    .disabled(!player.hasNext)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(HaloColor.text)
    }

    private var playSymbol: String {
        if player.isPlaying { return item.isLive ? "stop.fill" : "pause.fill" }
        return "play.fill"
    }

    private func skip(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .frame(width: 60, height: 60)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }
}

/// Slight shrink on press; the control answers the finger immediately.
struct PressScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(HaloMotion.quick, value: configuration.isPressed)
    }
}

/// The Halo dock: the glass surface holding the player's secondary controls.
struct HaloDock: View {
    var item: NowPlayingItem
    var accent: Color
    var openQueue: () -> Void

    @Environment(PlayerController.self) private var player
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 0) {
            if !item.isLive {
                toggle("shuffle", "Shuffle", isOn: player.queue.isShuffled) { player.toggleShuffle() }
                    .accessibilityValue(player.queue.isShuffled ? "On" : "Off")
                toggle(player.queue.repeatMode == .one ? "repeat.1" : "repeat", "Repeat",
                       isOn: player.queue.repeatMode != .off) { player.cycleRepeat() }
                    .accessibilityValue(repeatDescription)
                toggle("list.bullet", "Queue", isOn: false, action: openQueue)
            }
            output
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.xxs)
        .haloGlass(cornerRadius: Radius.large, tint: accent)
    }

    private var repeatDescription: String {
        switch player.queue.repeatMode {
        case .off: "Off"
        case .all: "All"
        case .one: "One song"
        }
    }

    private func toggle(_ symbol: String, _ title: String, isOn: Bool,
                        action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(enabled: settings.hapticsEnabled)
            action()
        } label: {
            cell(symbol, title, isOn: isOn)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(title)
    }

    private func cell(_ symbol: String, _ title: String, isOn: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 36, height: 28)
                .background(Capsule().fill(isOn ? accent.opacity(0.28) : .clear))
                .foregroundStyle(isOn ? accent : HaloColor.text)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(HaloColor.text.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
    }

    /// Our own icon and label; a transparent system route picker on top opens the real menu.
    private var output: some View {
        let route = player.outputRoute
        let external = route?.isExternal == true
        return cell(symbol(for: route), external ? route!.name : "Output", isOn: external)
            .overlay { RoutePicker().accessibilityHidden(true) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Output")
            .accessibilityValue(route?.name ?? "This iPhone")
            .accessibilityAddTraits(.isButton)
    }

    private func symbol(for route: OutputRoute?) -> String {
        switch route?.kind {
        case .bluetooth, .headphones: "headphones"
        case .airPlay: "airplayaudio"
        case .car: "car.fill"
        default: "airplayaudio"
        }
    }
}

/// The system AirPlay / Bluetooth picker, drawn invisibly so Halo's own cell shows through.
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .clear
        view.activeTintColor = .clear
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// A plain message for a playback problem, with the actions that can fix it.
struct PlaybackIssueCard: View {
    var issue: PlaybackIssue
    var playSimilar: () -> Void

    @Environment(PlayerController.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(issue.title, systemImage: issue == .offline ? "wifi.slash" : "exclamationmark.circle")
                .font(.subheadline.weight(.semibold))
            Text(issue.message).font(.footnote).foregroundStyle(HaloColor.text.opacity(0.75))
            HStack(spacing: Spacing.xs) {
                ForEach(issue.actions, id: \.self) { action in
                    Button(title(action)) { perform(action) }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, Spacing.sm).padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.14)))
                }
            }
            .padding(.top, 2)
        }
        .foregroundStyle(HaloColor.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .haloGlass(cornerRadius: Radius.medium)
    }

    private func title(_ action: PlaybackIssue.Action) -> String {
        switch action {
        case .retry: "Try again"
        case .skip: "Skip"
        case .playSimilar: "Play something similar"
        }
    }

    private func perform(_ action: PlaybackIssue.Action) {
        switch action {
        case .retry: player.resume()
        case .skip: player.next()
        case .playSimilar: playSimilar()
        }
    }
}
