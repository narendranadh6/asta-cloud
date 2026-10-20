// swift-tools-version: 6.0
// Platform-neutral core of MUSE (networking, models, browser handoff logic).
// The full iOS app is generated from project.yml with XcodeGen; this package lets the
// core compile and run its unit tests anywhere `swift test` works (macOS or Linux CI).
import PackageDescription

let package = Package(
    name: "MUSECore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MUSECore", targets: ["MUSECore"])],
    targets: [
        .target(
            name: "MUSECore",
            path: "MUSE",
            exclude: [
                "App/AppModel.swift", "App/DiscoveryReminderScheduler.swift", "App/Info.plist",
                "App/MUSEApp.swift", "App/RootView.swift", "Core/DesignSystem", "Core/Persistence",
                "Features/AIDJ/AIDJView.swift", "Features/AIDJ/DraftEditor.swift", "Features/Home",
                "Features/Library", "Features/MoodHub", "Features/Onboarding",
                "Features/PlaylistStudio/PlaylistStudioView.swift", "Features/Search/SearchView.swift",
                "Features/Search/SongDetailView.swift", "Features/Settings", "Features/Shared.swift",
                "Features/Taste", "Resources", "Features/Discover/DiscoverView.swift",
                "Features/NowInBrave", "Core/DesignSystem/Showcase.swift", "Features/Radio",
            ],
            sources: [
                "Core/Networking",
                "Core/Models",
                "Core/BrowserIntegration",
                // UI-free view models, type-checked and unit tested off-device too.
                "App/AppSettings.swift",
                "Features/Search/SearchViewModel.swift",
                "Features/AIDJ/AIDJViewModel.swift",
                "Features/AIDJ/EditableDraft.swift",
                "Features/PlaylistStudio/PlaylistStudioViewModel.swift",
                "Features/Discover/DiscoverViewModel.swift",
            ]
        ),
        .testTarget(
            name: "MUSECoreTests",
            dependencies: ["MUSECore"],
            path: "Tests/MUSECoreTests",
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
