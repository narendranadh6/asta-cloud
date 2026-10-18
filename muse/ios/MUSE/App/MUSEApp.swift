import SwiftData
import SwiftUI

@main
struct MUSEApp: App {
    private let container: ModelContainer
    @State private var settings: AppSettings
    @State private var model: AppModel

    init() {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-MUSEInMemoryStore")
        let container: ModelContainer
        do {
            container = try LibrarySchema.makeContainer(inMemory: inMemory)
        } catch {
            // A corrupt store must not brick the app; fall back to memory and surface it.
            container = try! LibrarySchema.makeContainer(inMemory: true)
        }
        self.container = container
        let settings = AppSettings()
        // UI-test/screenshot mode: skip onboarding with a sample profile. Never used in normal runs.
        if ProcessInfo.processInfo.arguments.contains("-MUSEDemoOnboarded") {
            settings.hasCompletedOnboarding = true
            settings.displayName = ProcessInfo.processInfo.environment["MUSE_DEMO_NAME"] ?? "Alex"
            settings.preferredLanguage = "Telugu"
        }
        _settings = State(initialValue: settings)
        _model = State(initialValue: AppModel(
            api: AppModel.makeAPI(), settings: settings, context: container.mainContext,
            opener: UIApplicationURLOpener()))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(settings)
                .preferredColorScheme(.dark)
                .tint(MUSEColor.primary)
        }
        .modelContainer(container)
    }
}
