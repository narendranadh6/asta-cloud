# Brave integration

MUSE never plays audio or video itself. When you choose **Listen in Brave**, MUSE hands a
YouTube URL to Brave (or to iOS as a plain HTTPS link) and its involvement ends there.

## What was researched

Checked on **2026-10-18** against Brave's open-source iOS client
([brave/brave-core](https://github.com/brave/brave-core), `ios/brave-ios`):

| Source file | Finding |
|---|---|
| `App/iOS/SupportingFiles/Info.plist` | `CFBundleURLSchemes` = `http`, `https`, `$(BRAVE_URL_SCHEME)` |
| `App/Configuration/Base.xcconfig` | `BRAVE_URL_SCHEME = brave` (release). Beta: `brave-beta`, Nightly: `brave-nightly`, Debug: `brave-debug` |
| `Sources/Brave/Frontend/Browser/NavigationRouter.swift` | `<scheme>://open-url?url=<value>` reads the `url` query value with `URLComponents` and opens it in a tab. Also supports `?private=true`, `search?q=`, `open-text?text=` |
| `App/Shared/OpenInBraveViewController.swift` | Brave's own share extension builds `brave://open-url?url=…` the same way |

So `brave://open-url?url=<percent-encoded https URL>` is a public deep link that Brave
itself uses. It is not a private API, and MUSE does not use any undocumented behaviour.

MUSE only targets the release scheme `brave`. It doesn't query Beta or Nightly, to keep
`LSApplicationQueriesSchemes` minimal.

## Implementation

`ios/MUSE/Core/BrowserIntegration/`

* `YouTubeIdentifier.swift` validates video ids (`^[A-Za-z0-9_-]{11}$`) and playlist ids
  (known prefixes, 10–64 id characters), and builds canonical `https://www.youtube.com/…` URLs.
* `BraveURLBuilder.swift` builds `brave://open-url?url=…`. The nested URL is encoded with
  **RFC 3986 unreserved characters only**, so `&`, `=`, `?`, `/` and `#` are always escaped.
  `URLQueryItem` would leave `&` and `=` unescaped and could cut off a nested URL. Only
  HTTPS URLs on YouTube hosts are accepted.
* `BrowserHandoffService.swift`:

```swift
@MainActor protocol BrowserHandoffService: AnyObject {
    func canOpenBrave() -> Bool
    func destinationDescription() -> String
    func openYouTubeVideo(id: String) async throws -> HandoffResult
    func openYouTubePlaylist(id: String) async throws -> HandoffResult
}
```

`BraveBrowserHandoffService` works in this order:

1. Validate the id. Invalid ids throw before anything is opened.
2. If the preference is Brave and `canOpenURL(brave://)` is true, open the Brave deep link.
3. If Brave isn't installed, the open fails, or the preference is "Default browser", open
   the plain `https://www.youtube.com/…` URL.
4. If that also fails, throw `HandoffError.openFailed`. The UI shows an alert.

Demo-catalog tracks (used when the server has no YouTube key) are refused with
`HandoffError.demoContent`, so a fictional id is never opened.

`URLOpening` wraps `UIApplication.canOpenURL` / `open(_:options:)`, the supported Apple APIs.
Tests inject a fake opener. `Info.plist` declares `LSApplicationQueriesSchemes = [brave]`,
which `canOpenURL` requires.

### Unit tests (`ios/Tests/MUSECoreTests`)

* `YouTubeIdentifierTests`: valid and invalid ids, link parsing, host spoofing
  (`youtube.com.evil.example`), `javascript:` links.
* `BraveURLBuilderTests`: exact encoding, nested `&`/`=`/`#`, and a round trip through
  `URLComponents` exactly as Brave's router reads it.
* `BrowserHandoffServiceTests`: Brave installed, Brave missing, Brave open failing, user
  preference, both opens failing, invalid ids, playlists, demo tracks.

## Limitations (shown in the app)

MUSE **cannot**:

* control play or pause in Brave
* read Brave's queue, history or playback progress
* advance automatically to the next song of a MUSE playlist
* guarantee background playback
* block, skip or change YouTube ads
* download or extract audio

MUSE does **not** inject scripts into Brave, change YouTube pages, intercept traffic or touch
advertisements. Whatever Brave does with YouTube (Shields, background play settings) is
Brave's behaviour, under Brave's and YouTube's terms.

### Universal-link caveat

When the HTTPS fallback is used and the **YouTube app** is installed, iOS may route
`https://www.youtube.com/watch?...` to the YouTube app instead of a browser. That is iOS
behaviour. The Brave deep link avoids it because Brave opens the URL in its own tab.

## Real-device test checklist

**Status: not yet verified on hardware.** This development environment is Linux with no
iPhone. Don't consider the Brave integration working until every row below passes on a
physical iPhone.

Setup: iPhone on iOS 17 or later, MUSE installed from Xcode or TestFlight, backend reachable,
`MUSE_YOUTUBE_PROVIDER=youtube` with a real key.

| # | Scenario | Steps | Expected |
|---|---|---|---|
| 1 | Brave installed, Brave preferred | Search, open a song, tap **Listen in Brave** | Brave opens a new tab on the exact video. Settings → Browser handoff → "Last handoff: Brave" |
| 2 | Detection | Settings → Browser handoff | "Brave on this iPhone: Detected" |
| 3 | Brave not installed | Delete Brave, repeat #1 | Button caption says "Brave not detected". The HTTPS URL opens (Safari or the YouTube app). No crash |
| 4 | Default-browser preference | Pick "Default browser", repeat #1 | Brave is skipped. The HTTPS URL opens |
| 5 | Playlist link | Link a public YouTube playlist (Playlist → ⋯ → Link YouTube playlist), tap **YouTube playlist** | Brave opens `youtube.com/playlist?list=…` |
| 6 | Encoded URL integrity | Open a video whose page URL would carry extra params | Brave lands on the correct video, not a truncated URL |
| 7 | Return to MUSE | After #1, switch back | MUSE state is unchanged. No fake "now playing" UI |
| 8 | Brave private-only mode | Enable Brave "Private Browsing Only", repeat #1 | Brave opens a private tab, which is Brave's behaviour. MUSE reports success |
| 9 | Demo mode | Point at a backend without a YouTube key | Listen buttons are disabled with the demo explanation |
| 10 | Invalid id defence | (Unit-tested) | Nothing opens |
| 11 | VoiceOver | Enable VoiceOver, reach the Listen button | Reads the title and the destination hint |
| 12 | Brave Beta/Nightly only | Install only Brave Beta | "Not detected". HTTPS fallback is used (documented limitation) |

Record the iOS version, Brave version, device model and outcome of each run in the release
notes before claiming support.
