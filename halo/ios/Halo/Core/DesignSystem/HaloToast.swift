#if canImport(SwiftUI)
import SwiftUI

/// A short glass confirmation ("Saved to your library") that dismisses itself.
struct HaloToast: View {
    var text: String
    var systemImage: String?

    var body: some View {
        Group {
            if let systemImage {
                Label(text, systemImage: systemImage)
            } else {
                Text(text)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(HaloColor.text)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .haloGlass(cornerRadius: 22)
        .accessibilityAddTraits(.isStaticText)
    }
}

extension View {
    /// Shows `message` as a toast at `edge` for a moment, then clears it.
    func haloToast(_ message: Binding<String?>, edge: VerticalEdge = .bottom,
                   padding: CGFloat = Spacing.lg) -> some View {
        overlay(alignment: edge == .top ? .top : .bottom) {
            if let text = message.wrappedValue {
                HaloToast(text: text)
                    .padding(edge == .top ? .top : .bottom, padding)
                    .transition(.move(edge: edge == .top ? .top : .bottom).combined(with: .opacity))
                    .task(id: text) {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        message.wrappedValue = nil
                    }
                    .onAppear {
                        AccessibilityNotification.Announcement(text).post()
                    }
            }
        }
        .animation(HaloMotion.standard, value: message.wrappedValue)
    }
}
#endif
