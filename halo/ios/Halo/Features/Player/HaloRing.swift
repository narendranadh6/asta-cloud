import SwiftUI

/// Halo's signature for "waiting": a thin line of light travelling around the artwork's
/// edge while a song loads or buffers. It fades away as soon as sound starts. With Reduce
/// Motion it becomes a still, soft outline.
struct HaloRing: View {
    var active: Bool
    var cornerRadius: CGFloat
    var lineWidth: CGFloat = 2
    var gap: CGFloat = 5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if active {
                if reduceMotion {
                    shape.strokeBorder(.white.opacity(0.35), lineWidth: lineWidth)
                } else {
                    TimelineView(.animation) { context in
                        let period = 2.4
                        let turn = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: period) / period
                        shape.strokeBorder(
                            AngularGradient(
                                stops: [
                                    .init(color: .white.opacity(0), location: 0),
                                    .init(color: .white.opacity(0.95), location: 0.16),
                                    .init(color: .white.opacity(0), location: 0.34),
                                    .init(color: .white.opacity(0), location: 1),
                                ],
                                center: .center, angle: .degrees(turn * 360)),
                            lineWidth: lineWidth)
                    }
                }
            }
        }
        .padding(-gap)
        .animation(.easeOut(duration: 0.3), value: active)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius + gap, style: .continuous)
    }
}

/// Progress around the mini player's play button: elapsed time, or a travelling arc while
/// waiting. Reads the clock itself so only this small view redraws as time passes.
struct ProgressRing: View {
    var lineWidth: CGFloat = 2.5
    var color: Color = HaloColor.text

    @Environment(PlayerController.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            if player.phase.isWaiting && !reduceMotion {
                TimelineView(.animation) { context in
                    let turn = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1.2) / 1.2
                    arc(to: 0.22).rotationEffect(.degrees(turn * 360 - 90))
                }
            } else {
                arc(to: player.clock.fraction ?? 0).rotationEffect(.degrees(-90))
            }
        }
        .accessibilityHidden(true)
    }

    private func arc(to end: Double) -> some View {
        Circle()
            .trim(from: 0, to: end)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}
