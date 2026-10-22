// swift-tools-version: 6.0
// Platform-neutral core of Halo (networking, models, playback queue).
// The full iOS app is generated from project.yml with XcodeGen; this package lets the
// core compile and run its unit tests anywhere `swift test` works (macOS or Linux CI).
import PackageDescription

let package = Package(
    name: "HaloCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "HaloCore", targets: ["HaloCore"])],
    targets: [
        .target(
            name: "HaloCore",
            path: "Halo",
            exclude: [
                "App/AppModel.swift", "App/DiscoveryReminderScheduler.swift", "App/Info.plist",
                "App/HaloApp.swift", "App/RootView.swift", "Core/DesignSystem", "Core/Persistence",
                "Features/AIDJ/AIDJView.swift", "Features/AIDJ/DraftEditor.swift", "Features/Home/HomeView.swift",
                "Features/Library", "Features/MoodHub", "Features/Onboarding",
                "Features/PlaylistStudio/PlaylistStudioView.swift", "Features/Search/SearchView.swift",
                "Features/Search/SongDetailView.swift", "Features/Settings", "Features/Shared.swift",
                "Features/Taste", "Resources", "Features/Discover/DiscoverView.swift",
                "Features/Player", "Core/DesignSystem/Showcase.swift", "Features/Radio",
                "Core/Playback/StreamingAudioEngine.swift", "Core/Playback/SystemMediaControls.swift",
            ],
            sources: [
                "Core/Networking",
                "Core/Models",
                "Core/Playback",
                "Core/Artwork",
                "Core/Voice",
                // UI-free view models, type-checked and unit tested off-device too.
                "App/AppSettings.swift",
                "Features/Search/SearchViewModel.swift",
                "Features/AIDJ/AIDJViewModel.swift",
                "Features/AIDJ/EditableDraft.swift",
                "Features/PlaylistStudio/PlaylistStudioViewModel.swift",
                "Features/Discover/DiscoverViewModel.swift",
                "Features/Home/HomeViewModel.swift",
                "Features/Artist/PageLoader.swift",
            ]
        ),
        .testTarget(
            name: "HaloCoreTests",
            dependencies: ["HaloCore"],
            path: "Tests/HaloCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
