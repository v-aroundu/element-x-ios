//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias AppLockSetupSettingsScreenViewModelType = StateStoreViewModel<AppLockSetupSettingsScreenViewState, AppLockSetupSettingsScreenViewAction>

class AppLockSetupSettingsScreenViewModel: AppLockSetupSettingsScreenViewModelType, AppLockSetupSettingsScreenViewModelProtocol {
    private let appLockService: AppLockServiceProtocol
    private var actionsSubject: PassthroughSubject<AppLockSetupSettingsScreenViewModelAction, Never> = .init()
    
    var actions: AnyPublisher<AppLockSetupSettingsScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(appLockService: AppLockServiceProtocol) {
        self.appLockService = appLockService
        super.init(initialViewState: AppLockSetupSettingsScreenViewState(
            isMandatory: appLockService.isMandatory,
            isDummyPINEnabled: appLockService.isDummyPINEnabled,
            bindings: .init()))
    }
    
    // MARK: - Public
    
    override func process(viewAction: AppLockSetupSettingsScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .changePINCode:
            actionsSubject.send(.changePINCode)
        case .disable:
            showRemovePINAlert()
        case .changeDummyPINCode:
            actionsSubject.send(.changeDummyPINCode)
        case .removeDummyPINCode:
            showRemoveDummyPINAlert()
        }
    }
    
    // MARK: - Private
    
    private func showRemovePINAlert() {
        state.bindings.alertInfo = .init(id: .confirmRemovePINCode,
                                         title: L10n.screenAppLockSettingsRemovePinAlertTitle,
                                         message: L10n.screenAppLockSettingsRemovePinAlertMessage,
                                         primaryButton: .init(title: L10n.actionYes) { self.completeRemovePIN() },
                                         secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
    }
    
    private func completeRemovePIN() {
        appLockService.disable()
        actionsSubject.send(.appLockDisabled)
    }
    
    private func showRemoveDummyPINAlert() {
        state.bindings.alertInfo = .init(id: .confirmRemoveDummyPINCode,
                                         title: L10n.screenAppLockSettingsRemovePinAlertTitle,
                                         message: "Are you sure you want to remove the decoy PIN?",
                                         primaryButton: .init(title: L10n.actionYes) { self.completeRemoveDummyPIN() },
                                         secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
    }
    
    private func completeRemoveDummyPIN() {
        appLockService.removeDummyPINCode()
        state.isDummyPINEnabled = false
    }
}
