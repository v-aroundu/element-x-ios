# AppSettings — API Flows Guide

> A focused walkthrough of every system and external endpoint that `AppSettings.swift` connects to, how values flow through the app, and what happens at runtime.

---

## Table of Contents

1. [What AppSettings Is](#1-what-appsettings-is)
2. [How Values Are Stored — UserPreference & UserDefaults](#2-how-values-are-stored--userpreference--userdefaults)
3. [App Startup — How AppSettings Is Configured](#3-app-startup--how-appsettings-is-configured)
4. [Authentication API Flow — OIDC Configuration](#4-authentication-api-flow--oidc-configuration)
5. [Notification / Push API Flow](#5-notification--push-api-flow)
6. [Remote Settings Override Flow](#6-remote-settings-override-flow)
7. [Analytics API Flow](#7-analytics-api-flow)
8. [Bug Report / Rageshake API Flow](#8-bug-report--rageshake-api-flow)
9. [Maps API Flow](#9-maps-api-flow)
10. [Element Call Flow](#10-element-call-flow)
11. [Feature Flags — Local vs. Remote](#11-feature-flags--local-vs-remote)
12. [Build Type — How Release / Nightly / Debug Differ](#12-build-type--how-release--nightly--debug-differ)
13. [Quick Reference: Every External Endpoint in AppSettings](#13-quick-reference-every-external-endpoint-in-appsettings)

---

## 1. What AppSettings Is

`AppSettings` is the **single source of truth** for all user-facing configuration in the app. It is:

- A `final class` (not a struct) so it can be injected by reference.
- Registered globally via `ServiceLocator.shared.register(appSettings:)` on launch.
- Passed by reference into every service, coordinator, and view model that needs it.
- Never instantiated more than once. One instance per process (main app, NSE, share extension each get their own).

```
AppDelegate
  └── AppCoordinator.init()
        → AppHooks.appSettingsHook.configure(AppSettings())   ← creates & customises
        → ServiceLocator.shared.register(appSettings:)        ← stores globally
        → passes appSettings into every service that needs it
```

---

## 2. How Values Are Stored — UserPreference & UserDefaults

### The `@UserPreference` property wrapper

Almost every runtime-changeable setting in `AppSettings` is annotated with `@UserPreference`. This wrapper:

1. **Reads/writes from a `UserDefaults` suite** shared between the main app and the NSE (via an App Group).
2. **Emits Combine events** via a `PassthroughSubject` when the value changes — so any subscriber (e.g. `NotificationManager`) is immediately notified.
3. Supports **remote override** — a server-pushed value can shadow the local value without permanently overwriting it.

```swift
// How to subscribe to a setting change anywhere in the app:
appSettings.$enableNotifications
    .sink { newValue in
        // Called immediately with current value, then on every change
    }
    .store(in: &cancellables)
```

### Storage modes

| `storageType` | Where stored | Survives app restart? |
|---|---|---|
| `.userDefaults(store)` | Shared App Group UserDefaults | ✅ Yes |
| `.volatile` | In-memory only (also UserDefaults under the hood but resets) | ❌ No |

### The shared UserDefaults suite

```swift
private static var suiteName: String = InfoPlistReader.main.appGroupIdentifier
private static var store: UserDefaults! = UserDefaults(suiteName: suiteName)
```

The App Group identifier (e.g. `group.app.aroundu.messenger`) is read from `Info.plist`. This same suite is used by the **Notification Service Extension (NSE)**, allowing the NSE to read settings like `enableNotifications` without launching the main app.

### `RemotePreference<T>`

Some settings (`bugReportRageshakeURL`) are not stored in UserDefaults at all — they are `RemotePreference<T>` objects. These:
- Have a **hardcoded default** set at compile time.
- Can be **overridden at runtime** by the server pushing a new value.
- **Reset to default** when the session ends or `reset()` is called.
- Publish changes via a `CurrentValuePublisher` like a regular Combine subject.

---

## 3. App Startup — How AppSettings Is Configured

### Step 1 — Instantiation

```
AppCoordinator.init(appDelegate:)
  → let appSettings = AppHooks.appSettingsHook.configure(AppSettings())
```

`AppSettings()` is created with all its compile-time defaults. Then `AppSettingsHook.configure()` immediately calls `appSettings.override(...)` to apply the aroundU-specific overrides (homeserver lock, etc.).

### Step 2 — ServiceLocator registration

```swift
ServiceLocator.shared.register(appSettings: appSettings)
```

After this, any code can call `ServiceLocator.shared.settings` to get the instance (though direct injection is preferred).

### Step 3 — Target platform initialisation

```swift
targetConfiguration = Target.mainApp.configure(
    logLevel: appSettings.logLevel,
    traceLogPacks: appSettings.traceLogPacks,
    sentryURL: appSettings.bugReportSentryRustURL,
    rageshakeURL: appSettings.bugReportRageshakeURL,
    appHooks: appHooks
)
```

The Rust SDK's logging/tracing platform is initialised here with values read directly from `AppSettings`. The `rageshakeURL` `RemotePreference` publisher is also subscribed to here so that if the rageshake URL is pushed by the server later, the tracing config is automatically updated.

### Step 4 — `override()` for forks

`AppSettings` exposes a single `override(...)` method that takes every configurable URL and string. This is the **forking/white-labelling entry point** — a fork (like aroundU Messenger) calls this once at startup via `AppSettingsHook` to replace the Element defaults with their own values.

```
AppSettings defaults           →   override() called by AppSettingsHook
──────────────────────────────────────────────────────────────────────
accountProviders: ["matrix.org"]  →  ["messenger.aroundu.app"]
allowOtherAccountProviders: true  →  false   (no server picker)
pushGatewayBaseURL: ...           →  "https://push.aroundu.app"
```

---

## 4. Authentication API Flow — OIDC Configuration

### The `oidcConfiguration` lazy property

```swift
private(set) lazy var oidcConfiguration = OIDCConfiguration(
    clientName: InfoPlistReader.main.bundleDisplayName,
    redirectURI: oidcRedirectURL,           // https://element.io/oidc/login
    clientURI: websiteURL,
    logoURI: logoURL,
    tosURI: acceptableUseURL,
    policyURI: privacyURL,
    staticRegistrations: oidcStaticRegistrations.mapKeys { $0.absoluteString }
)
```

This is built **lazily** (once, on first access) from the other URL properties. If `override()` is called first (which it always is at startup), the URLs it picks up are already the fork-specific ones.

### How it reaches the SDK

```
AuthenticationService.urlForOIDCLogin()
  → AuthenticationClientFactory.makeClient(appSettings:)
      → ClientBuilder.baseBuilder(...)
            .oidcConfiguration(appSettings.oidcConfiguration.rustValue)
                                              ↑
                              OIDCConfiguration.rustValue converts the Swift struct
                              to MatrixRustSDK.OidcConfiguration
```

The `OIDCConfiguration.rustValue` computed property (in `OIDCConfiguration.swift`) maps the Swift struct to the SDK's `OidcConfiguration` type via the FFI bridge.

### OIDC static registrations

```swift
let oidcStaticRegistrations: [URL: String] = [
    "https://id.thirdroom.io/realms/thirdroom": "elementx"
]
```

These are pre-registered client IDs for specific OIDC providers that don't support dynamic registration. When the SDK contacts one of these issuers, it uses the pre-registered ID instead of performing a dynamic registration POST.

### `oidcRedirectURL`

```
"https://element.io/oidc/login"
```

This is a universal link. When the OIDC provider redirects back after login, iOS intercepts this URL and delivers it to the app via the `application(_:open:options:)` delegate. The app then calls `AuthenticationService.loginWithOIDCCallback(_:)`.

---

## 5. Notification / Push API Flow

This is the most network-intensive flow driven by `AppSettings`.

### 5.1 Key settings involved

| Setting | Default | Purpose |
|---|---|---|
| `pushGatewayBaseURL` | `https://push.aroundu.app` | Sygnal push gateway host |
| `pusherAppID` | `<bundleID>.ios` | Identifies this app to the push gateway |
| `pusherProfileTag` | random 16-char string | Groups push rules for this device |
| `enableNotifications` | `true` | Master on/off for push notifications |
| `enableInAppNotifications` | `true` | Whether to show banners while app is open |
| `lastNotificationBootTime` | — | Used by NSE to detect device restarts |

### 5.2 Push registration flow

```
AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
    → NotificationManager.register(with: deviceToken)
        → NotificationManager.setPusher(with:clientProxy:)
```

Inside `setPusher`:

```swift
PusherConfiguration(
    identifiers: .init(
        pushkey: deviceToken.base64EncodedString(),   // the APNS token
        appId: appSettings.pusherAppID                // e.g. "app.aroundu.messenger.ios"
    ),
    kind: .http(data: .init(
        url: appSettings.pushGatewayNotifyEndpoint.absoluteString,
        //   ↑ "https://push.aroundu.app/_matrix/push/v1/notify"
        format: .eventIdOnly,
        defaultPayload: APNSPayload(...)
    )),
    appDisplayName: "\(bundleDisplayName) (iOS)",
    deviceDisplayName: UIDevice.current.name,
    profileTag: pusherProfileTag(),                   // stored in UserDefaults
    lang: preferredLocale
)
→ clientProxy.setPusher(with: configuration)
    → SDK: PUT /_matrix/client/v3/pushers/set  (to the Matrix homeserver)
```

The **homeserver** stores the pusher. When a new message arrives for this user, the homeserver calls the push gateway (`https://push.aroundu.app/_matrix/push/v1/notify`), which then sends an APNS notification to Apple, which wakes the Notification Service Extension.

```
New message on homeserver
    → homeserver POSTs to https://push.aroundu.app/_matrix/push/v1/notify
        → Sygnal push gateway
            → Apple APNS
                → NSE wakes, decrypts notification
                    → iOS shows banner
```

### 5.3 `enableNotifications` toggle

`NotificationManager.start()` subscribes to the Combine publisher:

```swift
appSettings.$enableNotifications
    .sink { [weak self] newValue in
        self?.enableNotifications(newValue)
    }
```

- `true` → calls `requestAuthorization()` → registers for remote notifications → `setPusher` is called.
- `false` → calls `delegate?.unregisterForRemoteNotifications()` → iOS stops delivering APNS tokens → pusher is removed from the homeserver.

### 5.4 `enableInAppNotifications` toggle

Checked in the `UNUserNotificationCenterDelegate` callback:

```swift
func userNotificationCenter(_ center:, willPresent notification:) async -> UNNotificationPresentationOptions {
    guard appSettings.enableInAppNotifications else {
        return []   // suppress the banner entirely
    }
    // ... show badge, sound, banner
}
```

This setting **does not affect background / locked-screen** notifications — only banners while the app is in the foreground.

---

## 6. Remote Settings Override Flow

The `RemoteSettingsHook` system allows the server to push configuration changes to the app after login. The flow:

```
User logs in successfully
    → AppCoordinator.configureUserSession()
        → appHooks.remoteSettingsHook.initializeCache(using: client, applyingTo: appSettings)
            → client.elementWellKnown()                    ← fetches /.well-known/matrix/client
                → decodes ElementWellKnown JSON
                    → if enforceElementPro == true → error: user must use Element Pro
```

For aroundU Messenger, the `DefaultRemoteSettingsHook` implementation is mostly a pass-through — it checks the well-known for the `enforce_element_pro` flag but does not push additional settings overrides.

The `RemotePreference<T>` type is the mechanism for any setting that *can* be server-driven:

```swift
// AppSettings:
let bugReportRageshakeURL: RemotePreference<RageshakeConfiguration> = .init(...)

// Server can later push a new value:
appSettings.bugReportRageshakeURL.applyRemoteValue(.url(serverPushedURL))
```

---

## 7. Analytics API Flow

### Configuration

```swift
let analyticsConfiguration: AnalyticsConfiguration? = AppSettings.makeAnalyticsConfiguration()

private static func makeAnalyticsConfiguration() -> AnalyticsConfiguration? {
    guard let host = Secrets.postHogHost, let apiKey = Secrets.postHogAPIKey else { return nil }
    return AnalyticsConfiguration(host: host, apiKey: apiKey)
}
```

Analytics is **disabled at compile time** if `Secrets.postHogHost` / `Secrets.postHogAPIKey` are nil (which is the case for open-source builds). The `Secrets.swift` file in `Secrets/` controls this.

### Consent state

```swift
@UserPreference(key: UserDefaultsKeys.analyticsConsentState, defaultValue: .unknown, ...)
var analyticsConsentState
```

States: `.unknown` → `.optedIn` / `.optedOut`

The `AnalyticsService` reads `analyticsConsentState` and only sends events when the user has opted in. The `AppCoordinator` checks `appSettings.canPromptForAnalytics` to decide whether to show the consent screen during onboarding.

### PostHog endpoint

```
AnalyticsService → PostHogAnalyticsClient
    → HTTP POST to Secrets.postHogHost/capture   (e.g. https://posthog.element.io)
```

No Matrix Rust SDK involvement — this is a direct `URLSession` call made by the `PostHog` analytics library.

---

## 8. Bug Report / Rageshake API Flow

### Rageshake

```swift
let bugReportRageshakeURL: RemotePreference<RageshakeConfiguration> = .init(
    Secrets.rageshakeURL.map { .url(URL(string: $0)!) } ?? .disabled
)
```

- If `Secrets.rageshakeURL` is set (e.g. `https://rageshake.element.io/api/submit`) → the rageshake service is enabled.
- The URL can be **remotely overridden** via the `RemotePreference` system.
- The `BugReportService` reads this URL and POSTs a multipart/form-data report with logs and screenshots.

### Sentry (crash reporting)

```swift
let bugReportSentryURL: URL? = Secrets.sentryDSN.map { URL(string: $0)! }
let bugReportSentryRustURL: URL? = Secrets.sentryRustDSN.map { URL(string: $0)! }
```

Two separate Sentry DSNs:
- `bugReportSentryURL` → Swift-side crash/error reporting (via `Sentry` SDK).
- `bugReportSentryRustURL` → Rust-side panic/error reporting (via the MatrixRustSDK tracing integration).

Both are **nil** in open-source builds and only populated in official aroundU Messenger builds via the `Secrets.swift` file.

Sentry is **disabled by default** even when a DSN is present, and is only enabled after the user consents to analytics:

```
AppCoordinator.setupAnalytics()
    → analyticsService.startIfEnabled()
        → if user has opted in: enableSentryLogging(enabled: true)
```

---

## 9. Maps API Flow

```swift
private(set) var mapTilerConfiguration = MapTilerConfiguration(
    baseURL: "https://api.maptiler.com/maps",
    apiKey: Secrets.mapLibreAPIKey,
    lightStyleID: "streets-v2",
    darkStyleID: "streets-v2-dark"
)
```

When the user opens a location pin in a message, the app renders a `MapLibre` map view. The tile requests go to:

```
https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=<Secrets.mapLibreAPIKey>
```

The API key is loaded from `Secrets.mapLibreAPIKey` (also nil in open-source builds). If nil, the map view shows an error instead of tiles. The `mapTilerConfiguration` can be replaced via `override()` for forks that use a different tile provider.

---

## 10. Element Call Flow

```swift
#if IS_MAIN_APP
let elementCallBaseURL: URL = EmbeddedElementCall.appURL!
#endif

@UserPreference(key: UserDefaultsKeys.elementCallBaseURLOverride, ...)
var elementCallBaseURLOverride: URL?
```

Element Call is **embedded** as a local web app (via the `EmbeddedElementCall` package). The actual URL opened in the call web view is:

```
elementCallBaseURLOverride ?? elementCallBaseURL
```

In production this is the embedded local URL. Developers can set `elementCallBaseURLOverride` to point at a staging or development call server (e.g. `https://call.element.dev`) via developer options, without rebuilding.

The PostHog and Sentry credentials for Element Call analytics are separate constants (not stored in UserDefaults because users don't configure them):

```swift
let elementCallPosthogAPIHost = "https://posthog-element-call.element.io"
let elementCallPosthogAPIKey  = "phc_..."
let elementCallPosthogSentryDSN = "https://...@sentry.tools.element.io/41"
```

These are passed to the call web view via a URL fragment / query parameter when launching a call.

---

## 11. Feature Flags — Local vs. Remote

Feature flags in `AppSettings` fall into two categories:

### Local flags (stored in UserDefaults)

These persist across app restarts and can be toggled in the Developer Options screen:

```swift
@UserPreference(key: .threadsEnabled, defaultValue: false, storageType: .userDefaults(store))
var threadsEnabled

@UserPreference(key: .knockingEnabled, defaultValue: false, storageType: .userDefaults(store))
var knockingEnabled

@UserPreference(key: .linkPreviewsEnabled, defaultValue: false, storageType: .userDefaults(store))
var linkPreviewsEnabled
```

### Volatile flags (in-memory only)

These reset to their defaults every time the app launches. Used for features still under active development where you don't want stale state:

```swift
@UserPreference(key: .spaceFiltersEnabled, defaultValue: true, storageType: .volatile)
var spaceFiltersEnabled

@UserPreference(key: .createSpaceEnabled, defaultValue: true, storageType: .volatile)
var createSpaceEnabled
```

### Build-type defaults

Some flags default to `true` only in debug builds:

```swift
@UserPreference(key: .viewSourceEnabled, defaultValue: appBuildType == .debug, ...)
var viewSourceEnabled

@UserPreference(key: .developerOptionsEnabled, defaultValue: appBuildType == .debug, ...)
var developerOptionsEnabled
```

This means the "View Source" and "Developer Options" items are hidden in production release builds unless the user explicitly enables them.

---

## 12. Build Type — How Release / Nightly / Debug Differ

```swift
static var appBuildType: AppBuildType {
    #if DEBUG
    return .debug
    #else
    switch InfoPlistReader.main.baseBundleIdentifier {
    case "app.aroundu.messenger.nightly":
        return .nightly
    default:
        return .release
    }
    #endif
}
```

| Build | `baseBundleIdentifier` | Effect on settings |
|---|---|---|
| Debug | any | `developerOptionsEnabled = true`, `viewSourceEnabled = true` |
| Nightly | `app.aroundu.messenger.nightly` | Same defaults as Release but identifiable by bundle ID |
| Release | `app.aroundu.messenger` | `developerOptionsEnabled = false`, `viewSourceEnabled = false` |

The build type also affects:
- **`pusherAppID`** — always `<baseBundleIdentifier>.ios`, so Debug, Nightly, and Release each register a **separate pusher** on the homeserver. This prevents Nightly push tokens from overwriting Release ones.
- **`backgroundAppRefreshTaskIdentifier`** — hardcoded to `app.aroundu.messenger.background.refresh`, so only the release app registers this background task (Nightly uses the same identifier, which is intentional for shared testing).

---

## 13. Quick Reference: Every External Endpoint in AppSettings

| Property | Default value | Protocol | When used |
|---|---|---|---|
| `pushGatewayNotifyEndpoint` | `https://push.aroundu.app/_matrix/push/v1/notify` | HTTPS POST | Registered as pusher on homeserver; called by homeserver on new messages |
| `oidcRedirectURL` | `https://element.io/oidc/login` | Universal Link / HTTPS | OIDC callback after browser login |
| `websiteURL` | `https://element.io` | HTTPS | Shown in OIDC client metadata |
| `logoURL` | `https://element.io/mobile-icon.png` | HTTPS | Shown in OIDC consent screen |
| `acceptableUseURL` | `https://element.io/acceptable-use-policy-terms` | HTTPS | Shown in OIDC consent screen (ToS) |
| `privacyURL` | `https://element.io/privacy` | HTTPS | Shown in OIDC consent screen + settings |
| `copyrightURL` | `https://element.io/copyright` | HTTPS | Shown in About screen |
| `encryptionURL` | `https://element.io/help#encryption` | HTTPS | "Learn more" link in encryption banners |
| `deviceVerificationURL` | `https://element.io/help#encryption-device-verification` | HTTPS | "Learn more" in device verification |
| `chatBackupDetailsURL` | `https://element.io/help#encryption5` | HTTPS | "Learn more" in backup screen |
| `identityPinningViolationDetailsURL` | `https://element.io/help#encryption18` | HTTPS | "Learn more" in identity warning |
| `historySharingDetailsURL` | `https://element.io/en/help#e2ee-history-sharing` | HTTPS | "Learn more" in history sharing |
| `mapTilerConfiguration.baseURL` | `https://api.maptiler.com/maps` | HTTPS | Map tile requests in location messages |
| `elementCallBaseURL` | Embedded local URL | Local | Element Call web view |
| `bugReportRageshakeURL` | From `Secrets.rageshakeURL` | HTTPS POST | Rageshake / bug report submission |
| `bugReportSentryURL` | From `Secrets.sentryDSN` | HTTPS | Swift crash/error reporting |
| `bugReportSentryRustURL` | From `Secrets.sentryRustDSN` | HTTPS | Rust panic/error reporting |
| Analytics (PostHog) | From `Secrets.postHogHost` | HTTPS POST | Usage analytics (opt-in only) |
| `elementProAppStoreURL` | `https://apps.apple.com/...` | Deep link | Shown when server requires Element Pro |

> **Note:** All Matrix API calls (login, sync, send message, etc.) are **not** made directly by `AppSettings`. They go through the Matrix Rust SDK via `ClientProxy`. `AppSettings` only configures the *endpoints and metadata* used to set up those SDK calls.

---

## Summary Diagram

```
AppSettings
│
├── OIDC Config ──────────────────────────► AuthenticationService
│   (oidcConfiguration, oidcRedirectURL)       └── SDK: OIDC login flow
│                                                  └── HTTP to homeserver + OIDC provider
│
├── Push Config ──────────────────────────► NotificationManager
│   (pushGatewayBaseURL, pusherAppID,           └── SDK: PUT /pushers/set  (homeserver)
│    enableNotifications,                            └── Push gateway: push.aroundu.app
│    enableInAppNotifications)                            └── Apple APNS
│
├── Analytics Config ─────────────────────► AnalyticsService
│   (analyticsConfiguration,                    └── HTTP POST to PostHog
│    analyticsConsentState)
│
├── Bug Report Config ────────────────────► BugReportService + Sentry SDK
│   (bugReportRageshakeURL,                     └── HTTP POST to rageshake server
│    bugReportSentryURL)                         └── HTTP to Sentry DSN
│
├── Maps Config ──────────────────────────► MapLibre view
│   (mapTilerConfiguration)                     └── HTTP GET tile requests to MapTiler
│
├── Element Call Config ──────────────────► ElementCallService
│   (elementCallBaseURL,                        └── Local or remote call web app URL
│    elementCallBaseURLOverride)
│
└── Feature Flags ────────────────────────► All ViewModels / Coordinators
    (threadsEnabled, knockingEnabled,           └── Guard conditions around UI features
     spaceFiltersEnabled, etc.)
```
