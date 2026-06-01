//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum AppLockPromptScreenViewModelAction {
    /// The user tapped "Enable App Lock" to proceed with setup.
    case enableAppLock
    /// The user tapped "Maybe Later" to skip the prompt.
    case skip
}

struct AppLockPromptScreenViewState: BindableState {
    let title: String = L10n.screenAppLockPromptTitle
    let subtitle: String = L10n.screenAppLockPromptSubtitle
}

enum AppLockPromptScreenViewAction {
    /// The user wants to enable app lock.
    case enable
    /// The user wants to skip the prompt.
    case skip
}
