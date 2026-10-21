import SwiftUI

/// The mini player's text and buttons. Its artwork and glass are drawn by `PlayerLayer`, so
/// they can grow into Now Playing. Swipe sideways on the text to skip.
struct MiniPlayerContent: View {
    var item: NowPlayingItem
    /// Horizontal drag in progress (moves the text with the finger).
    var swipe: CGFloat

    @Environment(PlayerController.self) private var player
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // The layer draws the artwork here.
            Color.clear.frame(width: PlayerGeometry.miniArt, height: PlayerGeometry.miniArt)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HaloColor.text)
                    .lineLimit(1)
                statusLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: swipe)
            .opacity(1 - min(abs(swipe) / 160, 0.6))
            playButton
            if !item.isLive {
                Button {
                    Haptics.tap(enabled: settings.hapticsEnabled)
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!player.hasNext)
                .accessibilityLabel("Next song")
            }
        }
        .foregroundStyle(HaloColor.text)
        .padding(.leading, (PlayerGeometry.miniHeight - PlayerGeometry.miniArt) / 2)
        .padding(.trailing, Spacing.xs)
        .clipped()
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 4) {
            if item.isLive {
                Text("LIVE").font(HaloFont.eyebrow).foregroundStyle(HaloColor.secondary)
            }
            if let issue = player.phase.issue {
                Text(issue.title).foregroundStyle(HaloColor.danger)
            } else {
                Text(item.subtitle).foregroundStyle(HaloColor.text.opacity(0.65))
            }
        }
        .font(.caption)
        .lineLimit(1)
    }

    private var playButton: some View {
        Button {
            Haptics.tap(enabled: settings.hapticsEnabled)
            player.togglePlayPause()
        } label: {
            ZStack {
                ProgressRing()
                Image(systemName: playSymbol)
                    .font(.system(size: 14, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 34, height: 34)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(player.isPlaying ? (item.isLive ? "Stop" : "Pause") : "Play")
    }

    private var playSymbol: String {
        if player.isPlaying { return item.isLive ? "stop.fill" : "pause.fill" }
        return "play.fill"
    }
}
