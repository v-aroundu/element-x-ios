# MapLibre / MapTiler Setup Guide

> How to enable the location sharing and map display features in aroundU Messenger iOS.

---

## Table of Contents

1. [What Is MapLibre and Why Does It Need a Key?](#1-what-is-maplibre-and-why-does-it-need-a-key)
2. [What Happens Without a Key](#2-what-happens-without-a-key)
3. [Step-by-Step: Get a MapTiler API Key](#3-step-by-step-get-a-maptiler-api-key)
4. [Step-by-Step: Create Your Map Styles](#4-step-by-step-create-your-map-styles)
5. [Where to Put the Key in the Code](#5-where-to-put-the-key-in-the-code)
6. [The Full Configuration Chain](#6-the-full-configuration-chain)
7. [How the Code Uses the Key](#7-how-the-code-uses-the-key)
8. [Protecting Your Key (Don't Commit It)](#8-protecting-your-key-dont-commit-it)
9. [Testing That It Works](#9-testing-that-it-works)
10. [Quick Checklist](#10-quick-checklist)

---

## 1. What Is MapLibre and Why Does It Need a Key?

The app uses two separate things that are easy to confuse:

| Name | What it is | Role |
|---|---|---|
| **MapLibre GL Native** | An open-source rendering engine (Swift Package) | Renders the actual interactive map tiles on screen |
| **MapTiler** | A commercial map tile service | Provides the actual map tile data and styles that MapLibre renders |

Think of it this way:
- **MapLibre** = the map engine / renderer (like a browser)
- **MapTiler** = the map data provider (like a website the browser loads)

MapLibre itself is free and already bundled into the project (in `project.yml`):

```yaml
MapLibre:
  url: https://github.com/maplibre/maplibre-gl-native-distribution
  minorVersion: 6.22.1
```

**MapTiler is the paid service that requires an API key.** Without a valid MapTiler API key, the SDK cannot fetch map tiles, so maps won't load.

---

## 2. What Happens Without a Key

Right now in `Secrets/Secrets.swift`:

```swift
enum Secrets {
    static let mapLibreAPIKey: String? = "your_key"  // ← placeholder, not a real key
}
```

And in `AppSettings.swift`:

```swift
private(set) var mapTilerConfiguration = MapTilerConfiguration(
    baseURL: "https://api.maptiler.com/maps",
    apiKey: Secrets.mapLibreAPIKey,   // ← this is "your_key" — invalid
    lightStyleID: "9bc819c8-e627-474a-a348-ec144fe3d810",
    darkStyleID: "dea61faf-292b-4774-9660-58fcef89a7f3"
)
```

Because `apiKey` is a non-nil `"your_key"` string (and not `nil`), `isEnabled` returns `true`:

```swift
var isEnabled: Bool {
    apiKey != nil   // ← returns true even with "your_key"!
}
```

This means:
- The **location sharing button** in the composer toolbar will be **visible** (bad UX).
- When someone taps it or receives a shared location, **the map will fail to load** and show a blurry placeholder image instead.

To properly disable maps, you'd set `apiKey: nil`. To make maps work, you need a real key.

---

## 3. Step-by-Step: Get a MapTiler API Key

1. **Go to [https://www.maptiler.com](https://www.maptiler.com)** and create a free account.
   - The free tier gives you **100,000 map tile requests/month** — plenty for development.
   - For production, check MapTiler's pricing based on your expected traffic.

2. **Sign in** and go to your **[API Keys dashboard](https://cloud.maptiler.com/account/keys/)**.

3. Click **"Create a Key"**:
   - Give it a name (e.g., `aroundU Messenger iOS Dev`).
   - Optionally restrict it to your bundle ID (`app.aroundu.messenger`) for security.

4. **Copy the API key** — it looks like: `aBcDeFgHiJkLmNoPqRsT`

---

## 4. Step-by-Step: Create Your Map Styles

The `lightStyleID` and `darkStyleID` in `AppSettings.swift` point to specific map styles hosted on MapTiler.

### Option A: Use Built-in MapTiler Style IDs (simplest)

MapTiler has pre-built styles you can use directly without creating custom ones:

| Style Name | Style ID | Mode |
|---|---|---|
| `basic-v2` | `basic-v2` | Light |
| `basic-v2-dark` | `basic-v2-dark` | Dark |
| `streets-v2` | `streets-v2` | Light |
| `streets-v2-dark` | `streets-v2-dark` | Dark |
| `outdoor-v2` | `outdoor-v2` | Light/Outdoor |
| `satellite` | `satellite` | Satellite |

Just use those strings directly as your style IDs — no creation needed.

### Option B: Create Custom Styles (for branded maps)

1. Go to **[MapTiler Cloud → Maps](https://cloud.maptiler.com/maps/)**.
2. Click **"New Map"** or duplicate an existing style.
3. Customize colours, fonts, labels to match your brand.
4. Click **Save**.
5. The style's URL will look like:
   ```
   https://api.maptiler.com/maps/9bc819c8-e627-474a-a348-ec144fe3d810/style.json?key=YOUR_KEY
   ```
   The long UUID (`9bc819c8-e627-474a-a348-ec144fe3d810`) is your **style ID**.
6. Create a second style for dark mode.

> **Note:** The current `AppSettings.swift` already has two style IDs in it:
> ```
> lightStyleID: "9bc819c8-e627-474a-a348-ec144fe3d810"
> darkStyleID:  "dea61faf-292b-4774-9660-58fcef89a7f3"
> ```
> These are Element's own styles. They work with Element's API key but **not with yours**. You need to use style IDs from your own MapTiler account.

---

## 5. Where to Put the Key in the Code

There is exactly **one place** to put it: `Secrets/Secrets.swift`.

```
Secrets/
├── Secrets.pkl        ← source template (do not edit for the key directly)
└── Secrets.swift      ← ⭐ edit this file
```

Open `Secrets/Secrets.swift` and replace `"your_key"` with your real MapTiler API key:

```swift
enum Secrets {
    static let sentryDSN: String? = "https://username@sentry.localhost/project_id"
    static let sentryRustDSN: String? = "https://username@sentry.localhost/project_id"
    static let postHogHost: String? = "https://posthog.localhost"
    static let postHogAPIKey: String? = "your_key"
    static let rageshakeURL: String? = "https://rageshake.localhost/submit"
    static let mapLibreAPIKey: String? = "aBcDeFgHiJkLmNoPqRsT"  // ← your real key here
}
```

### Then update the style IDs in AppSettings.swift

**File:** `ElementX/Sources/Application/Settings/AppSettings.swift` (around line 384)

```swift
// BEFORE (using Element's style IDs — won't work with your key):
private(set) var mapTilerConfiguration = MapTilerConfiguration(
    baseURL: "https://api.maptiler.com/maps",
    apiKey: Secrets.mapLibreAPIKey,
    lightStyleID: "9bc819c8-e627-474a-a348-ec144fe3d810",
    darkStyleID: "dea61faf-292b-4774-9660-58fcef89a7f3"
)

// AFTER (using built-in style names — works with any key):
private(set) var mapTilerConfiguration = MapTilerConfiguration(
    baseURL: "https://api.maptiler.com/maps",
    apiKey: Secrets.mapLibreAPIKey,
    lightStyleID: "basic-v2",
    darkStyleID: "basic-v2-dark"
)

// OR (using your own custom style UUIDs from MapTiler Cloud):
private(set) var mapTilerConfiguration = MapTilerConfiguration(
    baseURL: "https://api.maptiler.com/maps",
    apiKey: Secrets.mapLibreAPIKey,
    lightStyleID: "your-light-style-uuid-here",
    darkStyleID: "your-dark-style-uuid-here"
)
```

---

## 6. The Full Configuration Chain

Here is exactly how the key flows from `Secrets.swift` all the way to the map URL:

```
Secrets.swift
    └── static let mapLibreAPIKey: String? = "aBcDeFgHiJkLmNoP..."
           │
           ▼
AppSettings.swift (line ~384)
    └── mapTilerConfiguration = MapTilerConfiguration(
              baseURL: "https://api.maptiler.com/maps",
              apiKey: Secrets.mapLibreAPIKey,          ← key injected here
              lightStyleID: "basic-v2",
              darkStyleID: "basic-v2-dark"
        )
           │
           ▼
AppSettingsHook.swift
    └── appSettings.override(..., mapTilerConfiguration: appSettings.mapTilerConfiguration)
           │  (passes unchanged into the overridden settings)
           ▼
TimelineViewModel.swift (line ~109)
    └── TimelineViewState(mapTilerConfiguration: appSettings.mapTilerConfiguration, ...)
           │
           ▼
MapURLs.swift (MapTilerConfiguration extension)
    └── func styleURL(for style: MapTilerStyle) -> URL? {
              guard let apiKey else { return nil }   ← gated here
              var url = baseURL
              url.appendPathComponent(styleID(for: style))
              url.append(queryItems: [URLQueryItem(name: "key", value: apiKey)])
              return url
        }
           │
           ▼
Final URL sent to MapLibre:
    https://api.maptiler.com/maps/basic-v2?key=aBcDeFgHiJkLmNoP.../style.json

    or for static tile images in the timeline:
    https://api.maptiler.com/maps/basic-v2/static/13.4050,52.5200,12/300x200@2x.png?key=...&attribution=false
```

---

## 7. How the Code Uses the Key

### 7.1 The `isEnabled` gate

**File:** `ElementX/Sources/Application/Settings/MapTilerConfiguration.swift`

```swift
struct MapTilerConfiguration {
    let apiKey: String?
    // ...
    var isEnabled: Bool {
        apiKey != nil
    }
}
```

This single property controls whether the feature is shown in the UI. It's checked in two places:

**1. Composer toolbar** — shows/hides the "Share location" attachment button:
```swift
// ComposerToolbarViewModel.swift
isLocationSharingEnabled: appSettings.mapTilerConfiguration.isEnabled
```

**2. Timeline location view** — enables tap-to-expand on received locations:
```swift
// LocationRoomTimelineView.swift
.onTapGesture {
    guard context.viewState.mapTilerConfiguration.isEnabled else { return }
    context.send(viewAction: .mediaTapped(itemID: timelineItem.id))
}
```

When `isEnabled` is `false`:
- The location sharing button is hidden in the composer.
- Received locations in the timeline show a blurred placeholder image (non-tappable).
- No MapTiler API calls are made.

### 7.2 Interactive map (full MLNMapView)

Used when the user taps a location in the timeline or shares their own location.

**File:** `ElementX/Sources/Other/MapLibre/MapLibreMapView.swift`

```swift
// The style URL is fetched from your MapTilerConfiguration
let mapView = MLNMapView(
    frame: .zero,
    styleURL: mapURLBuilder.interactiveMapURL(for: colorScheme == .dark ? .dark : .light)
)
// → https://api.maptiler.com/maps/basic-v2/style.json?key=YOUR_KEY
```

MapLibre's rendering engine downloads the style JSON, then fetches individual map tiles using the key embedded in the URL.

### 7.3 Static map thumbnail (in the timeline)

When a location message appears in chat, a static PNG image is shown instead of a full interactive map — much cheaper on resources.

**File:** `ElementX/Sources/Other/MapLibre/MapLibreStaticMapView.swift`

```swift
// Fetches a static PNG from MapTiler's Static Maps API
if let url = mapURLBuilder.staticMapTileImageURL(
    for: colorScheme.mapStyle,
    coordinates: coordinates,
    zoomLevel: zoomLevel,
    size: mapSize,
    attribution: mapTilerAttributionPlacement
) {
    AsyncImage(url: url) { ... }
}
// → https://api.maptiler.com/maps/basic-v2/static/13.405,52.52,12/300x200@2x.png?key=YOUR_KEY&attribution=false
```

This is just a regular `AsyncImage` call — SwiftUI downloads a PNG image over HTTPS. No MapLibre rendering involved.

---

## 8. Protecting Your Key (Don't Commit It)

The API key is a secret that costs money if someone else uses it. **Do not commit it to git.**

### Option 1: Tell git to ignore local changes to the file (recommended for solo devs)

```bash
git update-index --assume-unchanged Secrets/Secrets.swift
```

This tells git to pretend the file never changes, so `git diff` and `git commit` will never pick it up. This is already documented in `docs/FORKING.md`.

To undo this if you intentionally want to commit a change:
```bash
git update-index --no-assume-unchanged Secrets/Secrets.swift
```

### Option 2: Use environment variables + pkl (recommended for CI/teams)

The `Secrets.pkl` file already reads from environment variables:

```plaintext
# Secrets.pkl
mapLibreAPIKey: String? = read?("env:MAPLIBRE_API_KEY")
```

So you can:
1. Export your key as an environment variable: `export MAPLIBRE_API_KEY=aBcDeFgHiJkL`
2. Run `pkl eval -o Secrets/Secrets.swift Secrets/Secrets.pkl` — this regenerates `Secrets.swift` with the real key.
3. Never commit `Secrets.swift` (add it to `.gitignore` or use `assume-unchanged`).

In CI (Xcode Cloud, GitHub Actions, Fastlane):
- Store `MAPLIBRE_API_KEY` as a secret environment variable in your CI settings.
- Add the `pkl eval` command to your pre-build script.

### Option 3: Set `apiKey: nil` to fully disable maps

If you don't need location sharing at all:

```swift
// AppSettings.swift
private(set) var mapTilerConfiguration = MapTilerConfiguration(
    baseURL: "https://api.maptiler.com/maps",
    apiKey: nil,                          // ← fully disables the feature
    lightStyleID: "basic-v2",
    darkStyleID: "basic-v2-dark"
)
```

This hides the location button in the composer and shows blurred placeholders for received locations.

---

## 9. Testing That It Works

### Test 1: Static map in timeline
1. Have two users chat. One sends a location (can also be done with a test message with a `m.location` event).
2. Open the room on your device/simulator.
3. The location message should show a **real map thumbnail** (not a blurry grey image).

### Test 2: Interactive map
1. Tap the location thumbnail.
2. A full map view should open showing the pin on a real rendered map.

### Test 3: Location sharing
1. In a room, open the composer attachment picker (`+` button).
2. You should see a **"Location"** option (only appears when `isEnabled == true`).
3. Tap it. The live map should load and let you drop a pin or share your current location.

### Common Errors

| Problem | Likely Cause |
|---|---|
| Blurred map image in timeline | `apiKey` is `nil` or invalid, OR style ID doesn't exist for your account |
| Map loads but shows no tiles | Style ID is wrong — it must belong to your MapTiler account |
| `401 Unauthorized` in network logs | API key is wrong or has been revoked |
| "Location" button missing in composer | `mapTilerConfiguration.isEnabled` is `false` (i.e., `apiKey == nil`) |
| Map loads in light mode but not dark | `darkStyleID` is wrong |

---

## 10. Quick Checklist

- [ ] Created a MapTiler account at [maptiler.com](https://www.maptiler.com)
- [ ] Generated an API key from [MapTiler Cloud → Account → Keys](https://cloud.maptiler.com/account/keys/)
- [ ] Copied the API key into `Secrets/Secrets.swift` as `mapLibreAPIKey`
- [ ] Chose style IDs (either built-in like `basic-v2` / `basic-v2-dark`, or custom ones from your MapTiler account)
- [ ] Updated `lightStyleID` and `darkStyleID` in `AppSettings.swift` (line ~384)
- [ ] Ran the app — location thumbnail in timeline shows a real map
- [ ] Location button appears in the composer attachment picker
- [ ] Protected the key with `git update-index --assume-unchanged Secrets/Secrets.swift`

---

## File Reference Summary

| File | Purpose |
|---|---|
| `Secrets/Secrets.swift` | **Where your API key lives** |
| `Secrets/Secrets.pkl` | Template that reads from env vars to generate `Secrets.swift` |
| `ElementX/Sources/Application/Settings/MapTilerConfiguration.swift` | The `MapTilerConfiguration` struct + `isEnabled` gate |
| `ElementX/Sources/Application/Settings/AppSettings.swift` (line ~384) | **Where style IDs are set** |
| `ElementX/Sources/Other/MapLibre/MapURLs.swift` | Builds the final HTTPS URLs sent to MapTiler |
| `ElementX/Sources/Other/MapLibre/MapLibreMapView.swift` | Interactive full-screen map (MLNMapView wrapper) |
| `ElementX/Sources/Other/MapLibre/MapLibreStaticMapView.swift` | Static thumbnail image in the timeline |
| `ElementX/Sources/Other/MapLibre/MapLibreModels.swift` | Enums: `ShowUserLocationMode`, `MapTilerStyle`, `MapLibreError` |
| `ElementX/Sources/Other/MapLibre/LocationAnnotation.swift` | The pin marker annotation on the map |
| `ElementX/Sources/Screens/LocationSharing/` | The screens for picking and viewing locations |
| `project.yml` (line 140) | MapLibre Swift Package dependency declaration |
