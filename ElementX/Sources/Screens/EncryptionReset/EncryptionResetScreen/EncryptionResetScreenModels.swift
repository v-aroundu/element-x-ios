//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

enum EncryptionResetScreenViewModelAction {
    case requestPassword(passwordPublisher: PassthroughSubject<String, Never>)
    /// The homeserver requires OIDC approval. Open `url` in a web browser; fire
    /// `completionPublisher` (with `true`) once the user returns to the app after
    /// approving, or `false` if they cancelled.
    case openURL(URL)
    case resetFinished
    case cancel
}

struct EncryptionResetScreenViewState: BindableState {
    /// When non-nil the OIDC approval step is active: show the "open browser + continue" UI.
    var oidcApprovalURL: URL?
    
    private let listItem3AttributedText = {
        let boldPlaceholder = "{bold}"
        var finalString = AttributedString(L10n.screenCreateNewRecoveryKeyListItem3(boldPlaceholder))
        var boldString = AttributedString(L10n.screenCreateNewRecoveryKeyListItem3ResetAll)
        boldString.bold()
        finalString.replace(boldPlaceholder, with: boldString)
        return finalString
    }()
    
    var listItems: [AttributedString] {
        [
            AttributedString(L10n.screenCreateNewRecoveryKeyListItem1(InfoPlistReader.main.productionAppName)),
            AttributedString(L10n.screenCreateNewRecoveryKeyListItem2),
            listItem3AttributedText,
            AttributedString(L10n.screenCreateNewRecoveryKeyListItem4),
            AttributedString(L10n.screenCreateNewRecoveryKeyListItem5)
        ]
    }

    var bindings: EncryptionResetScreenViewStateBindings
}

struct EncryptionResetScreenViewStateBindings {
    var alertInfo: AlertInfo<UUID>?
}

enum EncryptionResetScreenViewAction {
    case reset
    case cancel
    /// User taps "Open in Browser" during the OIDC approval step.
    case openOIDCURL
    /// User taps "I've approved — Continue" after returning from the browser.
    case continueAfterOIDCApproval
}
