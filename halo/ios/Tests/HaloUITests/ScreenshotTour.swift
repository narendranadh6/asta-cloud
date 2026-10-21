import XCTest

/// Drives the app against a running backend (CI starts `python -m tests.e2e_server`)
/// and captures a screenshot of each main screen. Screenshots are attached to the test result and, when
/// HALO_SCREENSHOT_DIR is set (CI), written there as PNGs.
@MainActor
final class ScreenshotTour: XCTestCase {
    private var app: XCUIApplication!

    private func launch() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-HaloInMemoryStore", "-HaloUITestOnboarded"]
        app.launchEnvironment["HALO_API_BASE_URL"] =
            ProcessInfo.processInfo.environment["HALO_API_BASE_URL"] ?? "http://127.0.0.1:8000"
        app.launchEnvironment["HALO_DEMO_NAME"] = "Narendra"
        app.launch()
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["HALO_SCREENSHOT_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: url)
        }
    }

    private func settle(_ seconds: TimeInterval = 2.5) {
        _ = app.wait(for: .runningForeground, timeout: 5)
        Thread.sleep(forTimeInterval: seconds)  // let artwork load for the screenshot
    }

    private func tab(_ label: String) {
        let button = app.buttons[label].firstMatch
        if button.waitForExistence(timeout: 5) { button.tap() }
        settle()
    }

    /// Goes back one screen if there is a back button; never fails the tour.
    private func back() {
        let button = app.navigationBars.buttons.firstMatch
        if button.waitForExistence(timeout: 3) && button.isHittable { button.tap() }
        settle(1)
    }

    func testTour() {
        launch()
        // Wait for the server-driven feed (its language section) rather than a fixed delay.
        _ = app.staticTexts["Explore by language"].waitForExistence(timeout: 12)
        settle(2)
        snap("01-home")

        app.swipeUp()
        settle(1)
        snap("02-home-scrolled")
        app.swipeUp()
        settle(2)
        snap("02b-home-feed")
        app.swipeUp()
        settle(2)
        snap("02c-home-feed-more")
        for _ in 0..<4 { app.swipeDown() }
        settle(1)

        // The Discover chip sits off-screen in the horizontal chip row; reveal it first.
        let chip = app.buttons["Workout"].firstMatch
        if chip.waitForExistence(timeout: 5) { chip.swipeLeft(); settle(1) }
        for label in ["Discover", "See all"] {
            let link = app.buttons[label].firstMatch
            guard link.waitForExistence(timeout: 5), link.isHittable else { continue }
            link.tap()
            if app.navigationBars["Discover"].waitForExistence(timeout: 5) { break }
        }
        settle(4)
        snap("03-discover")
        app.swipeUp()
        settle(1)
        snap("03b-discover-listenbrainz")
        back()

        tab("Search")
        snap("04-search")
        let firstTrack = app.cells.element(boundBy: 2)
        if firstTrack.waitForExistence(timeout: 5) {
            firstTrack.tap()
            settle(3)
            snap("05-song-details")
            app.swipeUp()
            settle(1)
            snap("05b-song-musicbrainz")
            app.swipeDown()
            settle(1)
            // Play in the app, then open Now Playing from the mini player.
            let play = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Play'")).firstMatch
            if play.waitForExistence(timeout: 5) {
                play.tap()
                settle(4)
                snap("05c-mini-player")
                let mini = app.otherElements["miniPlayer"].firstMatch
                if mini.waitForExistence(timeout: 5) {
                    mini.tap()
                    settle(3)
                    snap("05d-now-playing")
                    let queue = app.buttons["Queue"].firstMatch
                    if queue.waitForExistence(timeout: 3) {
                        queue.tap()
                        settle(2)
                        snap("05e-queue")
                        let done = app.buttons["Done"].firstMatch
                        if done.waitForExistence(timeout: 3) { done.tap() }
                        settle(1)
                    }
                    app.swipeDown(velocity: .fast)
                    settle(1)
                }
            }
            // The artist behind the song, and one of their albums.
            let artist = app.buttons["artistLink"].firstMatch
            if artist.waitForExistence(timeout: 3), artist.isHittable {
                artist.tap()
                settle(4)
                snap("05f-artist")
                app.swipeUp()
                settle(2)
                let album = app.scrollViews.buttons.matching(
                    NSPredicate(format: "label CONTAINS[c] '20'")).firstMatch
                if album.waitForExistence(timeout: 3), album.isHittable {
                    album.tap()
                    settle(4)
                    snap("05g-album")
                    back()
                }
                back()
            }
        }

        tab("AI DJ")
        snap("06-ai-dj")
        let trip = app.buttons["Create a playlist for my trip"].firstMatch
        if trip.waitForExistence(timeout: 5) {
            trip.tap()
            settle(4)
            snap("07-ai-dj-reply")
            let review = app.buttons["Review & save queue"].firstMatch
            if review.waitForExistence(timeout: 8) {
                review.tap()
                settle(3)
                snap("08-review-queue")
                let save = app.buttons["Save playlist"].firstMatch
                if save.waitForExistence(timeout: 5) { save.tap(); settle(1) }
                back()
            }
        }

        let studio = app.buttons["Playlist Studio"].firstMatch
        if studio.waitForExistence(timeout: 3) {
            studio.tap()
            settle(2)
            snap("09-playlist-studio")
        }

        tab("Library")
        snap("10-library")

        tab("Home")
        let focus = app.buttons["Focus"].firstMatch
        if focus.waitForExistence(timeout: 5) {
            focus.tap()
            settle(2)
            snap("11-mood")
        }

        tab("Profile")
        snap("12-settings")
    }
}
