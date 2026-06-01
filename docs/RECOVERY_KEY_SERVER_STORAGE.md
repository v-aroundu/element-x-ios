# Recovery Key – Server-Side Storage & Automatic Handling

## Current Architecture (How It Works Today)

```
User taps "Generate Key"
        │
        ▼
SecureBackupRecoveryKeyScreenViewModel
        │  calls
        ▼
SecureBackupController.generateRecoveryKey()
        │  calls (via MatrixRustSDK)
        ▼
encryption.enableRecovery() / encryption.resetRecoveryKey()
        │
        ▼  returns a raw key string (e.g. "EsT1 bvUF ...")
        │
        ▼
Key is shown on screen → user must manually copy/write it down
Key is NEVER stored anywhere automatically — not on device, not on server
```

The recovery key is a **client-side-only secret**. The Matrix SDK (via Rust) derives it from your server-side Secret Storage encryption. The key is returned once as a plain string; after that it is gone from memory.

---

## Can the Key Be Stored Server-Side Automatically?

### Short Answer

**Yes — but within strict cryptographic limits you cannot fully bypass.**

Matrix's Secret Storage (the SSSS — Server-Side Secret Storage and Sharing) is already the "server-side storage" mechanism. The recovery key is the passphrase that *unlocks* your SSSS. You cannot store the recovery key itself inside the thing it unlocks — that is circular.

However, **you can store the recovery key in a separate external store** (your own backend or a vault), and **auto-fetch + apply it** on the client without the user ever seeing it. The user experience can be completely transparent.

---

## Option A – Store in Apple Keychain (Recommended, On-Device)

This is the simplest path and does not require any server-side infrastructure.

### What to do

After `generateRecoveryKey()` succeeds, save the key to the iOS Keychain:

```swift
// After successful generation
case .success(let key):
    state.recoveryKey = key
    KeychainController.shared.setRecoveryKey(key, userID: userID)
```

On next login / recovery needed, auto-fetch and confirm:

```swift
if let storedKey = KeychainController.shared.recoveryKey(for: userID) {
    await secureBackupController.confirmRecoveryKey(storedKey)
    // Done — user never sees the recovery key screen
}
```

### Pros
- Zero server changes required
- Syncs across user's devices via iCloud Keychain
- Key never leaves Apple's secure enclave ecosystem

### Cons
- Lost if user gets a new device and doesn't have iCloud Keychain
- Not accessible on non-Apple platforms

---

## Option B – Store in Your Own Backend (True Server-Side)

You run a backend endpoint that stores and retrieves the recovery key per user, encrypted at rest.

### Architecture

```
[Client generates key]
        │
        ▼
POST /api/recovery-key
Body: { "user_id": "@alice:example.com", "key": "<encrypted_key>" }
        │
        ▼
[Your backend stores it, encrypted with user's account password or a server-managed KEK]

─────────────────────────────────────────────────

[User logs in on new device]
        │
        ▼
GET /api/recovery-key?user_id=@alice:example.com
        │  (authenticated request — bearer token / session)
        ▼
Client receives encrypted key → decrypts → calls confirmRecoveryKey()
        │
        ▼
Recovery is automatic — user never prompted
```

### What to implement on the iOS side

**1. Recovery Key Upload Service**

Create `ElementX/Sources/Services/SecureBackup/RecoveryKeyBackupService.swift`:

```swift
protocol RecoveryKeyBackupServiceProtocol {
    func storeRecoveryKey(_ key: String, for userID: String) async -> Result<Void, Error>
    func fetchRecoveryKey(for userID: String) async -> Result<String, Error>
}

final class RecoveryKeyBackupService: RecoveryKeyBackupServiceProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let authToken: String  // pass from UserSession

    func storeRecoveryKey(_ key: String, for userID: String) async -> Result<Void, Error> {
        // Encrypt key client-side before sending (see Encryption section below)
        let encryptedKey = encrypt(key, withPassword: userPassword)
        
        var request = URLRequest(url: baseURL.appendingPathComponent("recovery-key"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode([
            "user_id": userID,
            "key": encryptedKey
        ])
        
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200 ? .success(()) : .failure(...)
    }

    func fetchRecoveryKey(for userID: String) async -> Result<String, Error> {
        var request = URLRequest(url: baseURL.appendingPathComponent("recovery-key/\(userID)"))
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(RecoveryKeyResponse.self, from: data)
        let decryptedKey = decrypt(response.encryptedKey, withPassword: userPassword)
        return .success(decryptedKey)
    }
}
```

**2. Hook into Key Generation**

In `SecureBackupRecoveryKeyScreenViewModel`, after `generateRecoveryKey()` succeeds:

```swift
case .success(let key):
    state.recoveryKey = key
    // Auto-backup to server
    Task {
        await recoveryKeyBackupService.storeRecoveryKey(key, for: userID)
    }
```

**3. Auto-Recover on Login**

In the app startup / `UserSessionFlowCoordinator`, when `recoveryState == .incomplete` or `.disabled`:

```swift
func handleRecoveryStateIfNeeded() async {
    guard secureBackupController.recoveryState.value != .enabled else { return }
    
    switch await recoveryKeyBackupService.fetchRecoveryKey(for: userID) {
    case .success(let key):
        switch await secureBackupController.confirmRecoveryKey(key) {
        case .success:
            MXLog.info("Auto-recovery succeeded — user not prompted")
        case .failure:
            // Key on server is stale — fall through to manual recovery UI
            presentRecoveryKeyScreen()
        }
    case .failure:
        // No key on server yet — show normal recovery UI
        presentRecoveryKeyScreen()
    }
}
```

**Call this from the existing recovery check flow in `UserSessionFlowCoordinator`:**
Look for `case .presentRecoveryKeyScreen` in `HomeScreenCoordinator` / flow coordinator and insert the auto-fetch logic before showing the screen.

---

## ⚠️ Critical: Encrypt the Key Before Sending to Server

**Never send the raw recovery key to any server in plain text.**

Use a client-side encryption step:

```swift
import CryptoKit

func encrypt(_ key: String, withPassword password: String) -> String {
    let keyData = SymmetricKey(data: SHA256.hash(data: Data(password.utf8)))
    let keyBytes = Data(key.utf8)
    let sealedBox = try! AES.GCM.seal(keyBytes, using: keyData)
    return sealedBox.combined!.base64EncodedString()
}

func decrypt(_ base64: String, withPassword password: String) -> String {
    let keyData = SymmetricKey(data: SHA256.hash(data: Data(password.utf8)))
    let combined = Data(base64Encoded: base64)!
    let sealedBox = try! AES.GCM.SealedBox(combined: combined)
    let decrypted = try! AES.GCM.open(sealedBox, using: keyData)
    return String(data: decrypted, encoding: .utf8)!
}
```

The `password` here should be the user's Matrix account password or a separately derived key — **not** stored in the app bundle.

---

## Option C – Matrix Account Data (Built-In, No Extra Backend)

Matrix itself has a mechanism called **Account Data** (`m.account_data` events) that can store arbitrary JSON per user on the homeserver, encrypted via SSSS.

However, this has the same circularity problem: account data encrypted by SSSS needs the recovery key to decrypt. You cannot store the recovery key inside SSSS-encrypted account data.

**What you _can_ do:** Store a hint or a wrapped version of the key using a device-specific key (each device has its own cross-signing key). This is essentially what Matrix's Cross-Signing + SSSS already does for device keys. The recovery key is the *root* of this trust chain — it cannot be stored within it.

---

## Recommendation

| Use Case | Recommended Approach |
|---|---|
| Simple, Apple ecosystem only | **Option A** – iCloud Keychain |
| Multi-platform, own backend | **Option B** – Backend vault with client-side encryption |
| No extra infra, seamless | **Option A + B combined** — Keychain as primary, backend as fallback |

### Ideal UX Flow (Fully Automatic)

```
1. User generates recovery key (first time)
   → Saved silently to Keychain AND backend
   → "Done" button skips "copy key" step if auto-backup succeeded
   → Show subtle confirmation: "Recovery key saved securely"

2. User logs in on a new device
   → App checks: recoveryState == .incomplete?
   → Fetch key from backend (authenticated)
   → confirmRecoveryKey() called automatically
   → User never sees the recovery key screen at all

3. Backend key is stale / wrong
   → confirmRecoveryKey() fails
   → Fall back to normal recovery key screen
   → User enters key manually
   → New key stored to backend
```

---

## Where to Make Changes in the Codebase

| File | Change |
|---|---|
| `SecureBackupController.swift` | After `generateRecoveryKey()` — trigger backup upload |
| `SecureBackupRecoveryKeyScreenViewModel.swift` | Suppress "copy key" step if auto-backup succeeded |
| `UserSessionFlowCoordinator.swift` | Before presenting recovery key screen — try auto-fetch |
| New: `RecoveryKeyBackupService.swift` | Handle upload/fetch to your backend |
| `AppSettings.swift` | Add `recoveryKeyBackupEndpoint` config value |
| `Secrets.swift` | Store backend auth credentials |

---

## What Is NOT Possible

- You **cannot** eliminate the recovery key concept entirely — it is fundamental to Matrix E2EE.
- You **cannot** have the server generate or know the recovery key without the user's cooperation — doing so would break the E2EE security model (server would be able to read all messages).
- If you store the key on a backend **you control**, that backend can theoretically read messages. Make sure this is acceptable under your threat model and communicated to users.
