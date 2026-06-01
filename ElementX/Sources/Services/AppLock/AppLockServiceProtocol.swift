//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import LocalAuthentication

enum AppLockServiceError: Error {
    /// The operation failed to access the keychain.
    case keychainError
    /// The PIN code was rejected because it isn't long enough, or contains invalid characters.
    case invalidPIN
    /// The PIN code was rejected as an insecure choice.
    case weakPIN
    /// A PIN code hasn't been set yet.
    case pinNotSet
    /// The dummy PIN cannot be the same as the real PIN.
    case dummyPINMatchesRealPIN
}

/// The result of an attempt to unlock the app using a PIN code.
enum AppLockPINUnlockResult {
    /// The real PIN was entered — show real chats.
    case unlockedReal
    /// The dummy (duress) PIN was entered — show decoy chats.
    case unlockedDummy
    /// The PIN was incorrect.
    case failed
}

@MainActor
protocol AppLockServiceProtocol: AnyObject {
    /// The use of a PIN code is mandatory for this device.
    var isMandatory: Bool { get }
    /// The app has been configured to automatically lock with a PIN code.
    var isEnabled: Bool { get }
    
    /// A publisher that advertises when the service has been enabled or disabled.
    var isEnabledPublisher: AnyPublisher<Bool, Never> { get }
    
    /// Sets the user's real PIN code used to unlock the app.
    func setupPINCode(_ pinCode: String) -> Result<Void, AppLockServiceError>
    /// Validates the supplied PIN code is long enough, only contains digits and isn't a weak choice.
    func validate(_ pinCode: String) -> Result<Void, AppLockServiceError>
    /// Disables the App Lock feature, removing the user's stored PIN code.
    func disable()
    
    // MARK: Dummy PIN (Duress Mode)
    
    /// Whether or not a dummy (duress) PIN code has been configured.
    var isDummyPINEnabled: Bool { get }
    /// Sets the dummy PIN shown to a coercer. Must differ from the real PIN.
    func setupDummyPINCode(_ pinCode: String) -> Result<Void, AppLockServiceError>
    /// Removes the dummy PIN code.
    func removeDummyPINCode()
    
    // MARK: Unlock
    
    /// Informs the service that the app has entered the background.
    func applicationDidEnterBackground()
    /// Decides whether the app should be unlocked with a PIN code on foregrounding.
    func computeNeedsUnlock(didBecomeActiveAt date: Date) -> Bool
    
    /// Attempt to unlock the app with the supplied PIN code.
    /// Returns `.unlockedReal`, `.unlockedDummy`, or `.failed`.
    func unlock(with pinCode: String) -> AppLockPINUnlockResult
    
    /// The number of attempts the user had made to unlock with a PIN code.
    var numberOfPINAttempts: AnyPublisher<Int, Never> { get }
}

// sourcery: AutoMockable
extension AppLockServiceProtocol { }

extension AppLockServiceMock {
    static func mock(pinCode: String? = "2023", dummyPINCode: String? = nil, isMandatory: Bool = false, numberOfPINAttempts: Int = 0) -> AppLockServiceMock {
        let mock = AppLockServiceMock()
        mock.isEnabled = pinCode != nil
        mock.isMandatory = isMandatory
        mock.isDummyPINEnabled = dummyPINCode != nil
        mock.numberOfPINAttempts = CurrentValueSubject<Int, Never>(numberOfPINAttempts).eraseToAnyPublisher()
        mock.unlockWithClosure = { pin in
            if pin == pinCode { return .unlockedReal }
            if let dummyPINCode, pin == dummyPINCode { return .unlockedDummy }
            return .failed
        }
        return mock
    }
}
