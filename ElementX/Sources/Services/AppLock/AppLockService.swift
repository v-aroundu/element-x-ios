//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

/// The service responsible for locking and unlocking the app.
class AppLockService: AppLockServiceProtocol {
    private let keychainController: KeychainControllerProtocol
    private let appSettings: AppSettings
    
    private let timer: AppLockTimer
    
    var isMandatory: Bool {
        appSettings.appLockIsMandatory
    }
    
    var isEnabled: Bool {
        do {
            return try keychainController.containsPINCode()
        } catch {
            MXLog.error("Keychain access error: \(error)")
            MXLog.error("Locking the app.")
            return true
        }
    }
    
    private var isEnabledSubject: PassthroughSubject<Bool, Never> = .init()
    var isEnabledPublisher: AnyPublisher<Bool, Never> {
        isEnabledSubject.eraseToAnyPublisher()
    }
    
    var isDummyPINEnabled: Bool {
        keychainController.containsDummyPINCode()
    }
    
    var numberOfPINAttempts: AnyPublisher<Int, Never> {
        appSettings.$appLockNumberOfPINAttempts
    }
    
    init(keychainController: KeychainControllerProtocol, appSettings: AppSettings) {
        self.keychainController = keychainController
        self.appSettings = appSettings
        timer = AppLockTimer(gracePeriod: appSettings.appLockGracePeriod)
    }
    
    func setupPINCode(_ pinCode: String) -> Result<Void, AppLockServiceError> {
        let result = validate(pinCode)
        guard case .success = result else { return result }
        
        // Ensure real PIN doesn't match existing dummy PIN
        if let dummyPIN = keychainController.dummyPINCode(), dummyPIN == pinCode {
            return .failure(.dummyPINMatchesRealPIN)
        }
        
        do {
            try keychainController.setPINCode(pinCode)
            isEnabledSubject.send(true)
            return .success(())
        } catch {
            MXLog.error("Keychain access error: \(error)")
            return .failure(.keychainError)
        }
    }
    
    func validate(_ pinCode: String) -> Result<Void, AppLockServiceError> {
        guard pinCode.count == 4, pinCode.allSatisfy(\.isNumber) else { return .failure(.invalidPIN) }
        guard !appSettings.appLockPINCodeBlockList.contains(pinCode) else { return .failure(.weakPIN) }
        return .success(())
    }
    
    func setupDummyPINCode(_ pinCode: String) -> Result<Void, AppLockServiceError> {
        let result = validate(pinCode)
        guard case .success = result else { return result }
        
        // Dummy PIN must differ from the real PIN
        if let realPIN = keychainController.pinCode(), realPIN == pinCode {
            return .failure(.dummyPINMatchesRealPIN)
        }
        
        do {
            try keychainController.setDummyPINCode(pinCode)
            return .success(())
        } catch {
            MXLog.error("Keychain access error: \(error)")
            return .failure(.keychainError)
        }
    }
    
    func removeDummyPINCode() {
        keychainController.removeDummyPINCode()
    }
    
    func disable() {
        keychainController.removePINCode()
        keychainController.removeDummyPINCode()
        appSettings.appLockNumberOfPINAttempts = 0
        isEnabledSubject.send(false)
    }
    
    func applicationDidEnterBackground() {
        timer.applicationDidEnterBackground()
    }
    
    func computeNeedsUnlock(didBecomeActiveAt date: Date) -> Bool {
        timer.computeLockState(didBecomeActiveAt: date)
    }
    
    func unlock(with pinCode: String) -> AppLockPINUnlockResult {
        if pinCode == keychainController.pinCode() {
            completeUnlock()
            return .unlockedReal
        }
        
        if keychainController.containsDummyPINCode(), pinCode == keychainController.dummyPINCode() {
            // Don't reset attempts or touch the timer so that the real session stays locked.
            return .unlockedDummy
        }
        
        MXLog.warning("Wrong PIN entered.")
        appSettings.appLockNumberOfPINAttempts += 1
        return .failed
    }
    
    // MARK: - Private
    
    /// Shared logic for completing an unlock via the real PIN.
    private func completeUnlock() {
        timer.registerUnlock()
        appSettings.appLockNumberOfPINAttempts = 0
    }
}
