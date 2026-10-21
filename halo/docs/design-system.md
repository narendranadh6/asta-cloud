# Halo design system

Source: `ios/Halo/Core/DesignSystem/`. In debug builds, Settings → About → **Design system**
shows every token and component on one screen.

## Identity
* **Palette: Sunset Ember.** Warm coral (`primary` FF6B35) and magenta (`secondary` E83F6F),
  balanced by cool cyan (`accent` 4CC9F0) on charcoal. Gold (FFC145) is used sparingly.
* **The halo.** The orb and the coral-to-magenta ring are Halo's signature: AI DJ, artist portraits,
  selection and progress. Other products' shapes, icons and names are not used.
* **Type.** Expanded SF for display text (screen titles, rail headings, eyebrows) and standard SF for
  reading. Every style is a Dynamic Type text style.

## Tokens
| Token | Values | Use |
|---|---|---|
| `Spacing` | 4 · 8 · 12 · 16 · 24 · 32 · 48 | 16 screen gutter, 24 between rails |
| `Radius` | small 8 · medium 14 · large 22 | rows · cards · hero surfaces; always continuous corners |
| `ArtSize` | row 48 · compact 64 · card 140 · feature 180 · artist 112 | one size per role so rails line up |
| `Surface` | base · raised · overlay | elevation without heavy shadows |
| `HaloFont` | display · title · section · headline · body · meta · caption · eyebrow | type ramp |
| `HaloMotion` | standard spring · quick · emphasized · player · ambient | use `HaloMotion.animation(_:reduceMotion:)` |
| `HaloMaterial` | ground · glass · solid | glass only floats above the music, never on glass |

## Surfaces and artwork
* **`haloGlass()`** (`HaloGlass.swift`): mini player, dock, sheets, toasts. Liquid Glass on iOS 26,
  thin material with a top highlight before that; solid with Reduce Transparency, a clear edge with
  Increase Contrast. Primary controls and text are never glass.
* **`HaloArtwork`** (`Core/Artwork`): every cover in the app. Decoded at display size by
  `ArtworkPipeline`, kept in a memory cache, and prefetched for the previous and next songs.
* **`ArtworkPalette`**: base, glow and accent colors from a 24-pixel sample of the cover, computed
  off the main thread and cached per URL. White text on `base` is always at least 7:1; the accent is
  at least 3:1 on `base`. Covers that fail get a stable color from the artist name.

## Components
* **Rail**: title, optional eyebrow saying *why* the rail exists, optional "See all". Halo's unit of discovery.
* **ArtworkCard**, **ArtistBubble** (round with halo ring), **TrackCard** (Preview badge on 30-second previews), **SourceBadge** (Preview or source label), **TrackRow**.
* **SkeletonRail / SkeletonRow / SkeletonBlock**: placeholders at the real card sizes, so content doesn't
  shift when it arrives; the shimmer is off with Reduce Motion.
* **EmptyStateView**: always offers a next step. **ErrorStateView**: offline-aware, with retry.
* **NoticeBanner**: limitations stated inline, never hidden.

## Accessibility
Dynamic Type everywhere; Reduce Motion disables shimmer and springs; Reduce Transparency switches
glass to solid surfaces; cards combine into one VoiceOver element with a hint for the action.
