//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum AppLockSetupDummyPINScreenViewModelAction {
    case complete
    case cancel
}

enum AppLockSetupDummyPINScreenMode {
    case create
    case confirm
}

struct AppLockSetupDummyPINScreenViewState: BindableState {
    var mode: AppLockSetupDummyPINScreenMode = .create
    var numberOfConfirmAttempts = 0
    let maximumAttempts = 3
    
    var title: String {
        switch mode {
        case .create: return "Set Decoy PIN"
        case .confirm: return "Confirm Decoy PIN"
        }
    }
    
    var subtitle: String {
        switch mode {
        case .create: return "This PIN opens a fake chat list. Keep it different from your real PIN."
        case .confirm: return "Enter the decoy PIN again to confirm."
        }
    }
    
    var bindings: AppLockSetupDummyPINScreenViewStateBindings
}

struct AppLockSetupDummyPINScreenViewStateBindings {
    var pinCode = ""
    var alertInfo: AlertInfo<AppLockSetupDummyPINScreenAlertType>?
}

enum AppLockSetupDummyPINScreenAlertType {
    case weakPIN
    case pinMismatch
    case pinMatchesRealPIN
    case failedToSetPIN
}

enum AppLockSetupDummyPINScreenViewAction {
    case cancel
}
