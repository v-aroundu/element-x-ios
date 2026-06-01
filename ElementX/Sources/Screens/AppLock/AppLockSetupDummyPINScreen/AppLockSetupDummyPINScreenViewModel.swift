//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias AppLockSetupDummyPINScreenViewModelType = StateStoreViewModel<AppLockSetupDummyPINScreenViewState, AppLockSetupDummyPINScreenViewAction>

class AppLockSetupDummyPINScreenViewModel: AppLockSetupDummyPINScreenViewModelType {
    private let appLockService: AppLockServiceProtocol
    private let actionsSubject: PassthroughSubject<AppLockSetupDummyPINScreenViewModelAction, Never> = .init()
    
    /// The PIN entered in the create step, held for confirmation.
    private var newDummyPIN: String?
    
    var actions: AnyPublisher<AppLockSetupDummyPINScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(appLockService: AppLockServiceProtocol) {
        self.appLockService = appLockService
        
        super.init(initialViewState: AppLockSetupDummyPINScreenViewState(bindings: .init()))
        
        context.$viewState
            .map(\.bindings.pinCode)
            .removeDuplicates()
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] pinCode in
                guard pinCode.count == 4 else { return }
                self?.submit()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public
    
    override func process(viewAction: AppLockSetupDummyPINScreenViewAction) {
        switch viewAction {
        case .cancel:
            actionsSubject.send(.cancel)
        }
    }
    
    // MARK: - Private
    
    private func submit() {
        switch state.mode {
        case .create:
            createPIN()
        case .confirm:
            confirmPIN()
        }
    }
    
    private func createPIN() {
        let pinCode = state.bindings.pinCode
        if case let .failure(error) = appLockService.validate(pinCode) {
            MXLog.warning("Dummy PIN rejected: \(error)")
            showAlert(.weakPIN)
            return
        }
        
        newDummyPIN = pinCode
        state.mode = .confirm
        state.bindings.pinCode = ""
        state.numberOfConfirmAttempts = 0
    }
    
    private func confirmPIN() {
        let pinCode = state.bindings.pinCode
        guard pinCode == newDummyPIN else {
            MXLog.warning("Dummy PIN mismatch.")
            showAlert(.pinMismatch)
            return
        }
        
        switch appLockService.setupDummyPINCode(pinCode) {
        case .success:
            actionsSubject.send(.complete)
        case .failure(let error):
            MXLog.warning("Failed to set dummy PIN: \(error)")
            switch error {
            case .dummyPINMatchesRealPIN:
                showAlert(.pinMatchesRealPIN)
            case .keychainError:
                showAlert(.failedToSetPIN)
            default:
                showAlert(.weakPIN)
            }
        }
    }
    
    private func showAlert(_ type: AppLockSetupDummyPINScreenAlertType) {
        switch type {
        case .weakPIN:
            state.bindings.alertInfo = .init(id: type,
                                             title: L10n.screenAppLockSetupPinForbiddenDialogTitle,
                                             message: L10n.screenAppLockSetupPinForbiddenDialogContent,
                                             primaryButton: .init(title: L10n.actionOk) { self.state.bindings.pinCode = "" })
        case .pinMismatch:
            state.numberOfConfirmAttempts += 1
            state.bindings.alertInfo = .init(id: type,
                                             title: L10n.screenAppLockSetupPinMismatchDialogTitle,
                                             message: L10n.screenAppLockSetupPinMismatchDialogContent,
                                             primaryButton: .init(title: L10n.actionTryAgain) { self.restartIfNeeded() })
        case .pinMatchesRealPIN:
            state.bindings.alertInfo = .init(id: type,
                                             title: "Invalid Decoy PIN",
                                             message: "The decoy PIN cannot be the same as your real PIN. Choose a different PIN.",
                                             primaryButton: .init(title: L10n.actionOk) {
                                                 self.newDummyPIN = nil
                                                 self.state.mode = .create
                                                 self.state.bindings.pinCode = ""
                                             })
        case .failedToSetPIN:
            state.bindings.alertInfo = .init(id: type)
        }
    }
    
    private func restartIfNeeded() {
        state.bindings.pinCode = ""
        if state.numberOfConfirmAttempts >= state.maximumAttempts {
            newDummyPIN = nil
            state.mode = .create
            state.numberOfConfirmAttempts = 0
        }
    }
}
