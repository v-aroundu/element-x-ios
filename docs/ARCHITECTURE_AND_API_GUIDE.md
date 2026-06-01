# Element X iOS — Architecture, API Calls, Sync & Recovery Key Guide

> A complete walkthrough for developers unfamiliar with the iOS/Swift side of the project.

---

## Table of Contents

1. [High-Level Architecture Overview](#1-high-level-architecture-overview)
2. [The Matrix Rust SDK — The Real Engine](#2-the-matrix-rust-sdk--the-real-engine)
3. [How API Calls Are Made](#3-how-api-calls-are-made)
4. [The Sync Loop — How Messages Stay Live](#4-the-sync-loop--how-messages-stay-live)
5. [Room List & RoomSummaryProvider](#5-room-list--roomsummaryprovider)
6. [Timeline — Per-Room Messages](#6-timeline--per-room-messages)
7. [The MVVM + Coordinator Pattern](#7-the-mvvm--coordinator-pattern)
8. [HomeScreenViewModel Walkthrough](#8-homescreenviewmodel-walkthrough)
9. [Authentication & Session Restoration](#9-authentication--session-restoration)
10. [Recovery Key (Secure Backup) — Full Walkthrough](#10-recovery-key-secure-backup--full-walkthrough)
11. [Key Folder Map](#11-key-folder-map)
12. [Data Flow Diagram](#12-data-flow-diagram)

---

## 1. High-Level Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                         SwiftUI Views                        │
│  HomeScreen / RoomScreen / SettingsScreen / etc.             │
└──────────────────┬───────────────────────────────────────────┘
                   │  ViewActions (enum)
                   ▼
┌──────────────────────────────────────────────────────────────┐
│                       ViewModels                             │
│  HomeScreenViewModel / RoomScreenViewModel / etc.            │
│  (StateStoreViewModel — holds ViewState + processes Actions) │
└──────────────────┬───────────────────────────────────────────┘
                   │  async/await calls + Combine publishers
                   ▼
┌──────────────────────────────────────────────────────────────┐
│                     Service Layer (Proxies)                  │
│  ClientProxy  ←→  UserSession  ←→  RoomSummaryProvider       │
│  JoinedRoomProxy / TimelineProxy / SecureBackupController    │
└──────────────────┬───────────────────────────────────────────┘
                   │  FFI (Foreign Function Interface)
                   ▼
┌──────────────────────────────────────────────────────────────┐
│              MatrixRustSDK  (Rust, compiled to .xcframework) │
│  Client / SyncService / RoomListService / Timeline /         │
│  Encryption / Recovery                                       │
└──────────────────────────────────────────────────────────────┘
                   │  HTTPS / WebSocket
                   ▼
          Matrix Homeserver (e.g. matrix.org)
```

There are **no** hand-written HTTP requests like `URLSession.dataTask(url:)` anywhere in the app code for Matrix API calls. Everything goes through the **Matrix Rust SDK** via an FFI bridge (`MatrixRustSDK` Swift package). The Swift code only calls methods on SDK objects; the SDK talks to the server.

---

## 2. The Matrix Rust SDK — The Real Engine

**What it is:** A Rust library compiled into a native `.xcframework` and exposed to Swift via a generated FFI layer. It handles:

- All Matrix HTTP API calls (login, sync, send message, join room, etc.)
- Local SQLite storage of sessions, rooms, and timeline events
- End-to-end encryption (Olm/Megolm)
- Sliding Sync (the efficient incremental sync protocol)
- Key backup and recovery

**Where it is imported:**
```swift
import MatrixRustSDK
```
Every file in `ElementX/Sources/Services/` that talks to the server imports this.

**Key SDK types used in Swift:**
| SDK Type | Swift Wrapper | Purpose |
|---|---|---|
| `ClientProtocol` | `ClientProxy` | Main entry point — login, rooms, media |
| `SyncService` | internal in `ClientProxy` | Drives the sync loop |
| `RoomListService` | internal in `ClientProxy` | Provides the room list |
| `RoomListProtocol` | `RoomSummaryProvider` | Filtered/paginated room list |
| `Timeline` | `TimelineProxy` | Per-room message timeline |
| `Encryption` | `SecureBackupController` | E2E encryption & backup |
| `TaskHandle` | stored as `private var` | Retains a background listener |

---

## 3. How API Calls Are Made

### 3.1 Pattern: `async/await` wrapping SDK calls

Every API operation is an `async` Swift function that calls the SDK and either returns a `Result<T, Error>` or throws. Example — sending a message:

```
ViewModel.process(.sendMessage)
    → JoinedRoomProxy.sendMessage(...)          ← Swift proxy
        → timeline.send(...)                    ← SDK Timeline (Rust)
            → HTTP POST /_matrix/client/v3/rooms/{roomId}/send
```

### 3.2 Pattern: `ClientProxy` as the gateway

**File:** `ElementX/Sources/Services/Client/ClientProxy.swift`

`ClientProxy` wraps the SDK `ClientProtocol` object. Almost every feature goes through it:

```swift
// Example from ClientProxy.swift
func joinRoom(_ roomID: String, via: [String]) async -> Result<Void, ClientProxyError> {
    do {
        let _ = try await client.joinRoomByIdOrAlias(roomIdOrAlias: roomID, serverNames: via)
        await waitForRoomToSync(roomID: roomID, timeout: .seconds(30))
        return .success(())
    } catch {
        return .failure(.sdkError(error))
    }
}
```

- `client` here is `ClientProtocol` — the Rust SDK object.
- The `try await` is a **true async network call** going over HTTPS to your Matrix homeserver.
- The result is wrapped in Swift's `Result` type for clean error handling.

### 3.3 Pattern: Combine publishers for push-style updates

Some data (like the user's avatar URL, or display name) is fetched once and then "pushed" to the UI via Combine publishers:

```swift
// In ClientProxy.init
userSession.clientProxy.userAvatarURLPublisher
    .receive(on: DispatchQueue.main)
    .weakAssign(to: \.state.userAvatarURL, on: self)
    .store(in: &cancellables)
```

- `userAvatarURLPublisher` is a `CurrentValuePublisher<URL?, Never>`.
- When the SDK pushes a new avatar URL, this publisher emits, and the ViewModel's `state.userAvatarURL` updates automatically — causing SwiftUI to re-render.

### 3.4 Pattern: `SDKListener` — callbacks from Rust to Swift

The Rust SDK uses a **listener/callback** style for ongoing updates. The `SDKListener<T>` wrapper class in `ElementX/Sources/Other/SDKListener.swift` bridges these callbacks into the Swift world:

```swift
// SDKListener is a generic class that conforms to multiple SDK listener protocols
final class SDKListener<T> {
    private let onUpdateClosure: (T) -> Void
    init(_ onUpdateClosure: @escaping (T) -> Void) { ... }
}

// Usage — listening to encryption verification state
verificationStateListenerTaskHandle = client.encryption()
    .verificationStateListener(listener: SDKListener { [weak self] verificationState in
        Task { await self?.updateVerificationState(verificationState) }
    })
```

The returned `TaskHandle` **must be stored** in a property. If it gets deallocated, the listener is cancelled and you stop getting updates. That's why you see many `// periphery:ignore - retaining purpose` comments next to stored `TaskHandle` properties.

### 3.5 Error Handling Convention

All proxy functions return `Result<T, SomeError>`. The calling ViewModel checks the result with a `switch`:

```swift
switch await roomProxy.flagAsUnread(true) {
case .success:
    analyticsService.trackInteraction(name: .MobileRoomListRoomContextMenuUnreadToggle)
case .failure(let error):
    MXLog.error("Failed marking room as unread: \(error)")
}
```

`MXLog` is the internal logging system — it wraps Apple's `os.log` / `OSLog` for structured logging.

---

## 4. The Sync Loop — How Messages Stay Live

This is NOT traditional polling. Element X uses **Sliding Sync** (a Matrix protocol extension) which is a persistent, long-lived connection. Here's how the whole thing works:

### 4.1 What Sliding Sync is

In classic Matrix, sync is an HTTP long-poll: the client sends `GET /sync?timeout=30000`, the server holds the request open for up to 30 seconds, then returns any new events. The client immediately sends another request. This is called **long-polling**.

Sliding Sync improves on this by only sending the rooms you're currently looking at (your "viewport"), significantly reducing bandwidth and CPU usage. The SDK handles this automatically.

### 4.2 The Sync Service lifecycle

**File:** `ElementX/Sources/Services/Client/ClientProxy.swift`

```
AppCoordinator.startSync()
    → ClientProxy.startSync()
        → syncService.start()          ← Rust SyncService starts the loop
```

```swift
// ClientProxy.swift
func startSync() {
    guard !hasEncounteredAuthError else { return }
    guard networkMonitor.reachabilityPublisher.value == .reachable else { return }

    Task {
        await syncService.start()   // ← This kicks off Sliding Sync
    }
}
```

The `SyncService` (a Rust object) runs **indefinitely** in the background:
1. Sends a sync request to the homeserver (with the current "viewport" of rooms).
2. Server holds the connection open until there are new events (long-poll) OR until the 30-second timeout.
3. SDK processes the response, updates its local SQLite cache.
4. SDK fires listener callbacks for anything that changed.
5. Go back to step 1.

### 4.3 How sync state is observed

```swift
// In ClientProxy.init — observing the sync service state
syncServiceStateUpdateTaskHandle = createSyncServiceStateObserver(syncService)
```

The `SyncServiceStateObserver` callback (via `SDKListener`) fires whenever sync state changes (`.running`, `.terminated`, `.error`, etc.).

If it errors, the `ClientProxy` schedules a restart:

```swift
func restartSync() {
    restartTask = Task { [weak self] in
        try await Task.sleep(for: .milliseconds(250))  // small delay to avoid log flood
        self?.startSync()
    }
}
```

### 4.4 Network reachability integration

```swift
// In ClientProxy.init
networkMonitor.reachabilityPublisher
    .removeDuplicates()
    .receive(on: DispatchQueue.main)
    .sink { [weak self] reachability in
        if reachability == .reachable {
            self?.startSync()   // restart sync when network comes back
        }
    }
    .store(in: &cancellables)
```

When the device loses network (airplane mode, etc.), the sync loop stops. When network is restored, `startSync()` is called again automatically.

### 4.5 How updates reach the UI

```
SyncService (Rust) fires update
    → RoomListService listener (SDKListener<[RoomListEntriesUpdate]>)
        → RoomSummaryProvider.diffsPublisher.send(updates)
            → updateRoomsWithDiffs() applies diffs to local array
                → roomListSubject.send(updatedRooms)
                    → HomeScreenViewModel.updateRooms()
                        → state.rooms = newRooms
                            → SwiftUI re-renders HomeScreen
```

This entire chain is **push-based** — no polling from the UI side.

---

## 5. Room List & RoomSummaryProvider

**File:** `ElementX/Sources/Services/Room/RoomSummary/RoomSummaryProvider.swift`

### 5.1 What it does

`RoomSummaryProvider` is a live, filterable, paginated view of your rooms. The SDK sends it **diffs** (not full lists) whenever something changes — which is why the room list is fast.

There are **three** providers in `ClientProxy`:
| Provider | Purpose |
|---|---|
| `roomSummaryProvider` | The main filtered list shown in the home screen |
| `alternateRoomSummaryProvider` | An unfiltered "all rooms" snapshot (used for last-message search) |
| `staticRoomSummaryProvider` | A non-observable list (used for share sheets, forwarding, etc.) |

### 5.2 How filtering works

```swift
func setFilter(_ filter: RoomSummaryProviderFilter) {
    switch filter {
    case .excludeAll:
        _ = listUpdatesSubscriptionResult?.controller().setFilter(kind: .none)
    case let .search(query):
        _ = listUpdatesSubscriptionResult?.controller()
               .setFilter(kind: .all(filters: [.normalizedMatchRoomName(pattern: query), ...]))
    case let .all(filters):
        _ = listUpdatesSubscriptionResult?.controller()
               .setFilter(kind: .all(filters: filters.map(\.rustFilter)))
    }
}
```

Filters are passed **down to the Rust SDK** — the SDK re-evaluates the room list and sends back a new diff. No Swift-side sorting/filtering for name-match rooms.

Last-message content search IS done client-side in `HomeScreenViewState.visibleRooms`:

```swift
var visibleRooms: [HomeScreenRoom] {
    if bindings.isSearchFieldFocused, !bindings.searchQuery.isEmpty {
        let query = bindings.searchQuery.lowercased()
        var combined = rooms  // SDK name-matched rooms
        for room in allRoomsSnapshot {  // full snapshot from alternateProvider
            if let lastMessage = room.lastMessage,
               String(lastMessage.characters).lowercased().contains(query) {
                combined.append(room)
            }
        }
        return combined
    }
    return rooms
}
```

### 5.3 Pagination / Viewport

```swift
func updateVisibleRange(_ range: Range<Int>) {
    visibleItemRangePublisher.send(range)
}
```

The home screen calls `viewAction(.updateVisibleItemRange(range))` as the user scrolls. This tells the `RoomSummaryProvider` which items are visible. The provider then calls `subscribeToRooms(roomIds:)` on the SDK to ensure those rooms get full sync data.

---

## 6. Timeline — Per-Room Messages

**Files:**
- `ElementX/Sources/Services/Timeline/TimelineProxy.swift`
- `ElementX/Sources/Services/Timeline/TimelineItemProvider.swift`

### 6.1 How it's set up

When you open a room (`RoomFlowCoordinator`), a `TimelineProxy` is created for that room's SDK `Timeline` object. The proxy calls `subscribeForUpdates()`:

```swift
func subscribeForUpdates() async {
    await subscribeToPagination()
    let provider = await TimelineItemProvider(timeline: timeline, kind: kind, ...)
    await provider.waitForInitialItems()
    innerTimelineItemProvider = provider
    Task { await timeline.fetchMembers() }
}
```

Inside `TimelineItemProvider.init`:

```swift
roomTimelineObservationToken = await timeline.addListener(listener: SDKListener { [weak self] timelineDiffs in
    self?.serialDispatchQueue.sync {
        self?.updateItemsWithDiffs(timelineDiffs)
    }
})
```

This Rust listener fires every time new messages arrive (via sync) or old messages are loaded (via pagination). The diffs are applied to the local `itemProxies` array and published via Combine.

### 6.2 Back-pagination (loading older messages)

```swift
func paginateBackwards(requestSize: UInt16) async -> Result<Void, TimelineProxyError>
```

When the user scrolls to the top of the chat, the `RoomScreenViewModel` calls `paginateBackwards`. This calls `timeline.paginateBackwards(opts:)` in the SDK, which sends a `GET /messages` HTTP request to the homeserver to fetch older events. The results are fed back through the same diff listener.

---

## 7. The MVVM + Coordinator Pattern

The app follows a strict **MVVM + Coordinator** architecture:

```
AppCoordinator
  └── UserSessionFlowCoordinator
        ├── ChatsTabFlowCoordinator
        │     └── HomeScreenCoordinator
        │           ├── HomeScreenViewModel  ←→  HomeScreen (SwiftUI View)
        │           └── RoomFlowCoordinator
        │                 └── RoomScreenCoordinator
        │                       └── RoomScreenViewModel  ←→  RoomScreen
        └── SettingsFlowCoordinator
              └── ...
```

- **View** (SwiftUI): Only renders state. Never calls services directly.
- **ViewModel** (`StateStoreViewModel`): Holds `ViewState` + processes `ViewAction`s. Talks to services.
- **Coordinator**: Owns navigation. Listens to ViewModel's `actions` publisher and pushes/pops screens.
- **Flow Coordinator**: Manages a navigation flow (multi-step process like onboarding or settings).

### StateStoreViewModel

All ViewModels inherit from `StateStoreViewModel<State, Action>`. It provides:
- `state`: The published struct that SwiftUI binds to.
- `context`: An `ObservableObject` the View observes.
- `process(viewAction:)`: Override point to handle user actions.

---

## 8. HomeScreenViewModel Walkthrough

**File:** `ElementX/Sources/Screens/HomeScreen/HomeScreenViewModel.swift`

This is the ViewModel you currently have open. Here's what each major section does:

### 8.1 Initialization

```swift
init(userSession:, selectedRoomPublisher:, appSettings:, ...)
```

1. **Stores dependencies** (all injected, nothing created here).
2. **Grabs the room summary providers** from `userSession.clientProxy`.
3. **Calls `super.init`** with the initial `HomeScreenViewState`.
4. **Sets up Combine subscriptions** — each one watches a publisher and updates `state` when something changes.
5. **Calls `setupRoomListSubscriptions()`** — subscribes to room list updates.
6. **Calls `updateRooms()`** — does an initial population of the room list.

### 8.2 Security Banner Logic

```swift
userSession.sessionSecurityStatePublisher
    .receive(on: DispatchQueue.main)
    .sink { [weak self] securityState in
        switch securityState.recoveryState {
        case .disabled:
            state.securityBannerMode = .show(.setUpRecovery)    // "Set up recovery key"
        case .incomplete:
            state.securityBannerMode = .show(.recoveryOutOfSync) // "Confirm your key"
        default:
            state.securityBannerMode = .none
        }
    }
```

This is how the yellow "Set up recovery" banner appears at the top of the home screen. The recovery state comes from the `SecureBackupController` → `Encryption` SDK object.

### 8.3 Processing View Actions

```swift
override func process(viewAction: HomeScreenViewAction) {
    switch viewAction {
    case .selectRoom(let roomIdentifier):
        actionsSubject.send(.presentRoom(roomIdentifier: roomIdentifier))  // tells coordinator
    case .leaveRoom(let roomIdentifier):
        startLeaveRoomProcess(roomID: roomIdentifier)  // shows confirmation alert
    case .markRoomAsRead(let roomIdentifier):
        Task { ... await roomProxy.markAsRead(...) }   // async API call
    ...
    }
}
```

Actions from the View go into `process(viewAction:)`. The ViewModel either:
- Updates `state` directly (pure UI state change).
- Sends an action to `actionsSubject` (tells the Coordinator to navigate somewhere).
- Starts an async `Task` to make an API call.

---

## 9. Authentication & Session Restoration

### 9.1 New Login

**File:** `ElementX/Sources/Services/Authentication/AuthenticationService.swift`

```
User enters homeserver address
    → AuthenticationService.configure(for:)
        → AuthenticationClientFactory.makeClient(...)
            → ClientBuilder.baseBuilder(...)
                   .slidingSyncVersionBuilder(.discoverNative)
                   .sqliteStore(...)
                   .serverNameOrHomeserverUrl(...)
                   .build()                          ← Rust builds the Client, hits /.well-known
    → AuthenticationService returns LoginHomeserver (with supported login modes)

User chooses OIDC login
    → AuthenticationService.urlForOIDCLogin()        ← SDK builds OIDC URL
    → App opens Safari / ASWebAuthenticationSession
    → User logs in on browser, gets redirected back
    → AuthenticationService.loginWithOIDCCallback(_:)
        → client.loginWithOidcCallback(callbackUrl:) ← SDK completes OIDC flow

OR user enters username/password
    → AuthenticationService.login(username:password:)
        → client.login(username:password:...)        ← SDK POST /login
```

After successful login:
```
AuthenticationService.userSession(for: client)
    → UserSessionStore.userSession(for:sessionDirectories:passphrase:)
        → Saves RestorationToken to Keychain
        → Creates ClientProxy(client:)
        → Returns UserSession
```

### 9.2 Session Restoration (App Restart)

**File:** `ElementX/Sources/Services/UserSession/UserSessionStore.swift`

```swift
func restoreUserSession() async -> Result<UserSessionProtocol, UserSessionStoreError> {
    let credentials = keychainController.restorationTokens().first  // read from Keychain
    
    // Restore the SDK client from stored session data
    let client = try await ClientBuilder
        .baseBuilder(..., slidingSync: .restored, ...)
        .sqliteStore(config: .init(dataPath: ..., cachePath: ...))
        .build()
    
    let clientProxy = try await ClientProxy(client: client, ...)
    return .success(UserSession(clientProxy: clientProxy, ...))
}
```

The `RestorationToken` in the Keychain contains everything needed to restore the session (access token, homeserver URL, session directories, device ID, etc.) without asking the user to log in again.

### 9.3 ClientBuilder — Base Configuration

**File:** `ElementX/Sources/Other/Extensions/ClientBuilder.swift`

The `baseBuilder` static method applies all common settings:

```swift
ClientBuilder()
    .crossProcessStoreLocksHolderName(...)   // safe shared SQLite access with NSE
    .enableOidcRefreshLock()                 // auto-refresh OIDC tokens
    .setSessionDelegate(...)                 // saves new tokens to Keychain
    .userAgent(...)                          // HTTP User-Agent header
    .requestConfig(.init(retryLimit: 3, timeout: 30_000))   // retry logic
    .autoEnableCrossSigning(true)            // E2E: auto cross-sign new devices
    .backupDownloadStrategy(.afterDecryptionFailure)
    .autoEnableBackups(true)                 // auto-enable key backup
```

---

## 10. Recovery Key (Secure Backup) — Full Walkthrough

This is one of the most complex parts of the app. Here's every layer.

### 10.1 What "Recovery Key" means

Matrix uses **end-to-end encryption (E2EE)**. Your messages are encrypted with per-room keys (Megolm). Those room keys are backed up to the server in an encrypted **key backup**. The key backup itself is protected by your **recovery key** (a long random string like `EsTG 5qYT Jwg1 ...`).

If you lose all your devices, you can enter this recovery key to download and decrypt all your backed-up room keys — restoring access to your message history.

### 10.2 The State Machine

**File:** `ElementX/Sources/Services/SecureBackup/SecureBackupControllerProtocol.swift`

```
SecureBackupRecoveryState:
    .unknown    → initial, hasn't been checked yet
    .disabled   → recovery key has never been set up → show "Set up recovery" banner
    .enabled    → recovery key exists and backup is current → all good
    .incomplete → recovery key exists but device doesn't have it / backup is out of sync
                  → show "Confirm your recovery key" banner
    .settingUp  → in progress (generating key, uploading backup)
```

```
SecureBackupKeyBackupState:
    .unknown    → hasn't been checked (also means "effectively disabled")
    .enabling   → being enabled right now
    .enabled    → key backup is active and uploading
    .disabling  → being disabled
```

### 10.3 How the state is observed

**File:** `ElementX/Sources/Services/SecureBackup/SecureBackupController.swift`

```swift
// In SecureBackupController.init
recoveryStateListenerTaskHandle = encryption.recoveryStateListener(
    listener: SDKListener { [weak self] state in
        switch state {
        case .unknown:  recoveryStateSubject.send(.unknown)
        case .enabled:  recoveryStateSubject.send(.enabled)
        case .disabled: recoveryStateSubject.send(.disabled)
        case .incomplete: recoveryStateSubject.send(.incomplete)
        }
    }
)
```

The Rust SDK fires this callback whenever recovery state changes (on startup, after generating a key, after confirming, etc.).

This feeds into `UserSession`:

```swift
// UserSession.swift
Publishers.CombineLatest(
    clientProxy.verificationStatePublisher,
    clientProxy.secureBackupController.recoveryState
)
.map { SessionSecurityState(verificationState: $0, recoveryState: $1) }
.sink { sessionSecurityStateSubject.send($0) }
```

Which feeds into `HomeScreenViewModel`:

```swift
userSession.sessionSecurityStatePublisher
    .sink { securityState in
        switch securityState.recoveryState {
        case .disabled:    state.securityBannerMode = .show(.setUpRecovery)
        case .incomplete:  state.securityBannerMode = .show(.recoveryOutOfSync)
        default:           state.securityBannerMode = .none
        }
    }
```

### 10.4 Setting up a recovery key for the first time

**User taps "Set up Recovery" banner**:
```
HomeScreen user taps banner
    → ViewAction: .setupRecovery
    → HomeScreenViewModel.process → actionsSubject.send(.presentSecureBackupSettings)
    → HomeScreenCoordinator → navigates to SecureBackupScreen
        → User taps "Set up recovery key"
            → SecureBackupController.generateRecoveryKey()
```

```swift
// SecureBackupController.swift
func generateRecoveryKey() async -> Result<String, SecureBackupControllerError> {
    // If recovery is already set up, reset the key; otherwise enable it fresh
    if recoveryState.value != .disabled {
        let key = try await encryption.resetRecoveryKey()   // ← Rust SDK
        return .success(key)
    }

    // Enable recovery for the first time
    let recoveryKey = try await encryption.enableRecovery(
        waitForBackupsToUpload: false,
        passphrase: nil,
        progressListener: SDKListener { state in
            switch state {
            case .starting, .creatingBackup, .creatingRecoveryKey, .backingUp:
                recoveryStateSubject.send(.settingUp)       // show progress UI
            case .done:
                recoveryStateSubject.send(.enabled)         // done!
            case .roomKeyUploadError:
                // error, but key was still generated
            }
        }
    )
    return .success(recoveryKey)
}
```

What `encryption.enableRecovery(...)` does under the hood (in Rust):
1. Generates a random recovery key (a 256-bit random string encoded in base-58).
2. Creates a new key backup on the server (`POST /_matrix/client/v3/room_keys/version`).
3. Sets up the SSSS (Secure Secret Storage System) on your account.
4. Uploads all existing room keys to the backup.
5. Returns the recovery key string to Swift.

The user is then shown the key and told to save it.

### 10.5 Confirming an existing recovery key

This happens when `recoveryState == .incomplete` (the device doesn't have the correct key material).

**User taps "Confirm recovery key" banner**:
```
ViewAction: .confirmRecoveryKey
    → actionsSubject.send(.presentRecoveryKeyScreen)
    → User enters their recovery key string
        → SecureBackupController.confirmRecoveryKey(key)
```

```swift
func confirmRecoveryKey(_ key: String) async -> Result<Void, SecureBackupControllerError> {
    try await encryption.recover(recoveryKey: key)   // ← Rust SDK
    return .success(())
}
```

What `encryption.recover(recoveryKey:)` does under the hood (in Rust):
1. Downloads the key backup from the server (`GET /_matrix/client/v3/room_keys/keys`).
2. Decrypts the backup using the provided recovery key.
3. Imports the decrypted room keys into the local store.
4. Now the device can decrypt any old messages.

### 10.6 Key Backup Upload (on logout)

Before logging out, the app waits for all room keys to be uploaded to the backup:

```swift
func waitForKeyBackupUpload(uploadStateSubject: CurrentValueSubject<SecureBackupSteadyState, Never>) async {
    try await encryption.waitForBackupUploadSteadyState(progressListener: SDKListener { state in
        switch state {
        case .waiting:                uploadStateSubject.send(.waiting)
        case .uploading(let backed, let total): uploadStateSubject.send(.uploading(...))
        case .done:                   uploadStateSubject.send(.done)
        case .error:                  uploadStateSubject.send(.error)
        }
    })
}
```

This ensures you don't lose message decryption keys when signing out.

### 10.7 Summary: Recovery Key Flow

```
[.disabled] ──── generateRecoveryKey() ──────────────────────────► [.enabled]
                         │
                    Rust SDK:
                    1. Generate 256-bit random key
                    2. POST /room_keys/version (create backup)
                    3. POST /room_keys/keys (upload all keys)
                    4. Store SSSS data on account
                    5. Return key string to user

[.incomplete] ─── confirmRecoveryKey(key) ───────────────────────► [.enabled]
                         │
                    Rust SDK:
                    1. GET /room_keys/keys (download backup)
                    2. Decrypt with provided key
                    3. Import keys into local store
```

---

## 11. Key Folder Map

```
ElementX/Sources/
│
├── Application/
│   ├── AppCoordinator.swift          ← App root: sets up everything, starts sync
│   ├── AppDelegate.swift             ← UIApplicationDelegate
│   └── Settings/                     ← AppSettings (UserDefaults wrappers)
│
├── FlowCoordinators/
│   ├── UserSessionFlowCoordinator.swift  ← Tab bar coordinator post-login
│   ├── ChatsTabFlowCoordinator.swift     ← Chats tab navigation
│   ├── RoomFlowCoordinator.swift         ← In-room navigation
│   └── AuthenticationFlowCoordinator.swift
│
├── Screens/
│   ├── HomeScreen/
│   │   ├── HomeScreenViewModel.swift     ← ⭐ The file you have open
│   │   ├── HomeScreenModels.swift        ← ViewState, ViewAction, HomeScreenRoom
│   │   ├── HomeScreenCoordinator.swift
│   │   └── View/                         ← SwiftUI views
│   ├── RoomScreen/                       ← In-room message view
│   └── SecureBackup/                     ← Recovery key screens
│
├── Services/
│   ├── Client/
│   │   ├── ClientProxy.swift             ← ⭐ Main gateway to the SDK
│   │   ├── ClientProxyProtocol.swift     ← Protocol + all available operations
│   │   └── Client.swift                  ← Small extension on ClientProtocol
│   │
│   ├── Authentication/
│   │   ├── AuthenticationService.swift   ← Login / OIDC
│   │   └── AuthenticationClientFactory.swift  ← ClientBuilder setup
│   │
│   ├── Session/
│   │   ├── UserSession.swift             ← Combines clientProxy + security state
│   │   └── UserSessionProtocol.swift
│   │
│   ├── UserSession/
│   │   ├── UserSessionStore.swift        ← Keychain + session restore
│   │   └── RestorationToken.swift        ← Codable struct saved to Keychain
│   │
│   ├── Room/
│   │   ├── JoinedRoomProxy.swift         ← Per-room operations (send, leave, etc.)
│   │   ├── InvitedRoomProxy.swift        ← Accept/decline invites
│   │   └── RoomSummary/
│   │       ├── RoomSummaryProvider.swift ← ⭐ Live filtered room list
│   │       └── RoomSummary.swift         ← Data model for a room row
│   │
│   ├── SecureBackup/
│   │   ├── SecureBackupController.swift  ← ⭐ Recovery key + key backup logic
│   │   └── SecureBackupControllerProtocol.swift
│   │
│   ├── Timeline/
│   │   ├── TimelineProxy.swift           ← Per-room timeline operations
│   │   └── TimelineItemProvider.swift    ← Diff-based timeline item list
│   │
│   └── SessionVerification/
│       └── SessionVerificationControllerProxy.swift  ← Device verification (emoji)
│
└── Other/
    ├── SDKListener.swift                 ← ⭐ Bridges Rust callbacks → Swift
    └── Extensions/
        └── ClientBuilder.swift           ← ⭐ Base SDK client configuration
```

---

## 12. Data Flow Diagram

### Message Received Flow

```
Homeserver sends new message
         │
         ▼
SyncService (Rust) receives it via long-poll HTTP response
         │
         ▼
RoomListService updates room's lastMessage and unreadCount
         │ (fires RoomListEntriesUpdate diff)
         ▼
RoomSummaryProvider.updateRoomsWithDiffs()
         │ (roomListSubject.send(updatedRooms))
         ▼
HomeScreenViewModel.setupRoomListSubscriptions() subscriber fires
         │
         ▼
HomeScreenViewModel.updateRooms()
         │ (state.rooms = newRooms)
         ▼
HomeScreenViewState.visibleRooms computed property returns updated list
         │ (Combine @Published triggers SwiftUI re-render)
         ▼
HomeScreen SwiftUI view updates the room cell (new lastMessage, new badge)
```

### Recovery Key Setup Flow

```
User taps "Set up recovery key" in UI
         │  ViewAction.setupRecovery
         ▼
HomeScreenViewModel → actionsSubject.send(.presentSecureBackupSettings)
         │
         ▼
HomeScreenCoordinator → push SecureBackupScreen
         │  User taps "Generate key"
         ▼
SecureBackupScreenViewModel → secureBackupController.generateRecoveryKey()
         │  async, awaits Rust SDK
         ▼
SecureBackupController → encryption.enableRecovery(...)
         │  Rust SDK:
         │  - Creates key backup on server (HTTP POST)
         │  - Uploads room keys (HTTP PUT)
         │  - Fires progressListener callbacks
         ▼
recoveryStateSubject.send(.enabled)
         │  Combine publisher
         ▼
UserSession.sessionSecurityStatePublisher emits new state
         │
         ▼
HomeScreenViewModel updates state.securityBannerMode = .none
         │
         ▼
Banner disappears from HomeScreen
```

---

## Quick Reference: "Where do I add X?"

| I want to... | File to edit |
|---|---|
| Add a new Matrix API call | `ClientProxy.swift` + `ClientProxyProtocol.swift` |
| Add a new room-level operation | `JoinedRoomProxy.swift` + `RoomProxyProtocol.swift` |
| Change what's shown in the room list row | `HomeScreenRoom` in `HomeScreenModels.swift` |
| Change how rooms are filtered | `RoomSummaryProvider.setFilter()` |
| Add a new security/encryption feature | `SecureBackupController.swift` |
| Add a new screen and navigate to it | Add to `HomeScreenViewModelAction` + handle in `HomeScreenCoordinator.swift` |
| Change what the home screen banner shows | `HomeScreenViewModel` security state sink + `HomeScreenRecoveryKeyConfirmationBanner.swift` |
| Change sync behavior | `ClientProxy.startSync()` / `restartSync()` |
