import SwiftData
import SwiftUI

@main
struct HaloApp: App {
    private let container: ModelContainer
    @State private var settings: AppSettings
    @State private var model: AppModel

    init() {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-HaloInMemoryStore")
        let container: ModelContainer
        do {
            container = try LibrarySchema.makeContainer(inMemory: inMemory)
        } catch {
            // A corrupt store must not brick the app; fall back to memory and surface it.
            container = try! LibrarySchema.makeContainer(inMemory: true)
        }
        self.container = container
        let settings = AppSettings()
        // UI tests only: skip onboarding with a test profile.
        if ProcessInfo.processInfo.arguments.contains("-HaloUITestOnboarded") {
            settings.hasCompletedOnboarding = true
            settings.displayName = ProcessInfo.processInfo.environment["HALO_DEMO_NAME"] ?? "Alex"
            settings.preferredLanguage = "Telugu"
        }
        _settings = State(initialValue: settings)
        _model = State(initialValue: AppModel(
            api: AppModel.makeAPI(), settings: settings, context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.player)
                .environment(settings)
                .preferredColorScheme(.dark)
                .tint(HaloColor.primary)
        }
        .modelContainer(container)
    }
}
