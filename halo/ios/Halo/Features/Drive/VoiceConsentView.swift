import SwiftUI

/// Shown before any audio or text would leave the iPhone. Declining is as easy as agreeing,
/// and the choice can be changed later in Settings › Voice & privacy.
struct VoiceConsentView: View {
    var disclosure: ProcessingDisclosure
    var answer: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text(disclosure.title).font(HaloFont.title)
                    row("What leaves your iPhone", disclosure.whatLeaves, symbol: "waveform")
                    row("Who processes it", disclosure.processedBy, symbol: "building.2")
                    row("What is kept", disclosure.retention, symbol: "trash.slash")
                    if let url = disclosure.policyURL {
                        Link("Read the provider's privacy policy", destination: url)
                    }
                    Text("You can type instead at any time, and change this in Settings › Voice & privacy.")
                        .font(.footnote)
                        .foregroundStyle(HaloColor.mutedText)
                }
                .padding(Spacing.lg)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Spacing.sm) {
                    Button { answer(true) } label: {
                        Text("Allow").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("consentAllow")
                    Button { answer(false) } label: {
                        Text("Don't allow").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("consentDecline")
                }
                .padding(Spacing.lg)
                .background(.bar)
            }
        }
        .interactiveDismissDisabled()
    }

    private func row(_ title: String, _ text: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.body)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(HaloColor.primary)
        }
        .accessibilityElement(children: .combine)
    }
}
