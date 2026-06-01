//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum AppLockSetupSettingsScreenViewModelAction {
    /// The user would like to change the real PIN code.
    case changePINCode
    /// The user would like to change the dummy (duress) PIN code.
    case changeDummyPINCode
    /// The user has disabled the App Lock feature.
    case appLockDisabled
}

struct AppLockSetupSettingsScreenViewState: BindableState {
    /// Whether App Lock is mandatory and can be disabled by the user.
    let isMandatory: Bool
    /// Whether a dummy (duress) PIN has been configured.
    var isDummyPINEnabled: Bool
    var bindings: AppLockSetupSettingsScreenViewStateBindings
}

struct AppLockSetupSettingsScreenViewStateBindings {
    var alertInfo: AlertInfo<AppLockSetupSettingsScreenAlertType>?
}

enum AppLockSetupSettingsScreenAlertType {
    /// The alert shown to confirm the user would like to remove their PIN.
    case confirmRemovePINCode
    /// The alert shown to confirm the user would like to remove the dummy PIN.
    case confirmRemoveDummyPINCode
}

enum AppLockSetupSettingsScreenViewAction {
    /// The user would like to enter a new real PIN code.
    case changePINCode
    /// The user would like to disable the App Lock feature.
    case disable
    /// The user would like to set/change the dummy PIN.
    case changeDummyPINCode
    /// The user would like to remove the dummy PIN.
    case removeDummyPINCode
}
