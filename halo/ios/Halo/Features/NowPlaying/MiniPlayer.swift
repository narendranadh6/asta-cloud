import SwiftUI

/// Compact player above the tab bar on every screen. Tap to open Now Playing.
struct MiniPlayer: View {
    @Environment(PlayerController.self) private var player
    @Environment(AppSettings.self) private var settings
    var open: () -> Void

    var body: some View {
        if let item = player.item {
            HStack(spacing: Spacing.sm) {
                ArtworkView(url: item.artworkURL, size: 44, cornerRadius: Radius.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.subheadline.weight(.semibold))
                        .foregroundStyle(HaloColor.text).lineLimit(1)
                    HStack(spacing: 4) {
                        if item.isLive {
                            Text("LIVE").font(HaloFont.eyebrow).foregroundStyle(HaloColor.secondary)
                        } else if item.track?.isPreview == true {
                            Text("PREVIEW").font(HaloFont.eyebrow).foregroundStyle(HaloColor.gold)
                        }
                        Text(statusText(item)).font(.caption).foregroundStyle(HaloColor.mutedText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    Haptics.tap(enabled: settings.hapticsEnabled)
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                if !item.isLive {
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.title3).frame(width: 40, height: 44)
                    }
                    .disabled(!player.hasNext)
                    .accessibilityLabel("Next song")
                }
            }
            .foregroundStyle(HaloColor.text)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Surface.overlay)
                    .overlay(alignment: .bottom) { progressLine }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    .shadow(color: HaloColor.primary.opacity(0.25), radius: 12, y: 4)
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.bottom, Spacing.xxs)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens Now Playing")
            .accessibilityIdentifier("miniPlayer")
        }
    }

    private var progressLine: some View {
        GeometryReader { proxy in
            let fraction = player.duration.map { $0 > 0 ? min(player.position / $0, 1) : 0 } ?? 0
            Rectangle()
                .fill(HaloColor.neon)
                .frame(width: proxy.size.width * fraction, height: 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func statusText(_ item: NowPlayingItem) -> String {
        switch player.state {
        case .loading: return "Loading…"
        case let .failed(message): return message
        default: return item.subtitle
        }
    }
}
