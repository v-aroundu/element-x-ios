//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias SecureBackupScreenViewModelType = StateStoreViewModelV2<SecureBackupScreenViewState, SecureBackupScreenViewAction>

class SecureBackupScreenViewModel: SecureBackupScreenViewModelType, SecureBackupScreenViewModelProtocol {
    private let secureBackupController: SecureBackupControllerProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    
    /// Guards against triggering `enableBackup()` multiple times while an enable is already in flight.
    private var isEnablingBackup = false
    
    private var actionsSubject: PassthroughSubject<SecureBackupScreenViewModelAction, Never> = .init()
    var actions: AnyPublisher<SecureBackupScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(secureBackupController: SecureBackupControllerProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         chatBackupDetailsURL: URL) {
        self.secureBackupController = secureBackupController
        self.userIndicatorController = userIndicatorController
        
        super.init(initialViewState: .init(chatBackupDetailsURL: chatBackupDetailsURL,
                                           bindings: SecureBackupScreenViewStateBindings(keyStorageEnabled: secureBackupController.keyBackupState.value.keyStorageToggleState)))
        
        secureBackupController.recoveryState
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.recoveryState, on: self)
            .store(in: &cancellables)
        
        secureBackupController.keyBackupState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.state.keyBackupState = state
                self.state.bindings.keyStorageEnabled = state.keyStorageToggleState
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public
    
    override func process(viewAction: SecureBackupScreenViewAction) {
        switch viewAction {
        case .recoveryKey:
            actionsSubject.send(.manageRecoveryKey)
        case .keyStorageToggled(let enable):
            let keyBackupState = secureBackupController.keyBackupState.value
            switch (keyBackupState, enable) {
            case (.unknown, true):
                // Prevent double-triggering if an enable is already in flight.
                guard !isEnablingBackup else {
                    // Keep the toggle in sync with the real state.
                    state.bindings.keyStorageEnabled = keyBackupState.keyStorageToggleState
                    break
                }
                state.bindings.keyStorageEnabled = keyBackupState.keyStorageToggleState // Reset the toggle in case enabling fails
                Task { await enableBackup() }
            case (.enabled, false):
                state.bindings.keyStorageEnabled = keyBackupState.keyStorageToggleState // Reset the toggle in case the user cancels
                actionsSubject.send(.disableKeyBackup)
            default:
                // Toggling while backup is in a transitional state (enabling/disabling) — 
                // bring the toggle back in sync with the real state to avoid UI drift.
                state.bindings.keyStorageEnabled = keyBackupState.keyStorageToggleState
            }
        }
    }
    
    // MARK: - Private
    
    private func enableBackup() async {
        guard !isEnablingBackup else { return }
        isEnablingBackup = true
        
        let loadingIndicatorIdentifier = "SecureBackupScreenLoading"
        userIndicatorController.submitIndicator(.init(id: loadingIndicatorIdentifier, type: .modal, title: L10n.commonLoading, persistent: true))
        switch await secureBackupController.enable() {
        case .success:
            break
        case .failure(let error):
            MXLog.error("Failed enabling key backup with error: \(error)")
            state.bindings.alertInfo = .init(id: .init())
        }
        
        userIndicatorController.retractIndicatorWithId(loadingIndicatorIdentifier)
        isEnablingBackup = false
    }
}

extension SecureBackupKeyBackupState {
    var keyStorageToggleState: Bool {
        switch self {
        case .unknown, .enabling: false
        case .enabled, .disabling: true
        }
    }
}
