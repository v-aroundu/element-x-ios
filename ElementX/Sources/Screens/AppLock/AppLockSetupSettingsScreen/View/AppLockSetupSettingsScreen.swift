//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct AppLockSetupSettingsScreen: View {
    @ObservedObject var context: AppLockSetupSettingsScreenViewModel.Context
    
    var body: some View {
        Form {
            // MARK: Real PIN
            Section {
                ListRow(label: .plain(title: L10n.screenAppLockSettingsChangePin),
                        kind: .button { context.send(viewAction: .changePINCode) })
                    .accessibilityIdentifier(A11yIdentifiers.appLockSetupSettingsScreen.changePIN)
                
                if !context.viewState.isMandatory {
                    ListRow(label: .plain(title: L10n.screenAppLockSettingsRemovePin, role: .destructive),
                            kind: .button { context.send(viewAction: .disable) })
                        .accessibilityIdentifier(A11yIdentifiers.appLockSetupSettingsScreen.removePIN)
                }
            } header: {
                Text("Real PIN")
            }
            
            // MARK: Dummy (Duress) PIN
            Section {
                if context.viewState.isDummyPINEnabled {
                    ListRow(label: .plain(title: "Change Decoy PIN"),
                            kind: .button { context.send(viewAction: .changeDummyPINCode) })
                    ListRow(label: .plain(title: "Remove Decoy PIN", role: .destructive),
                            kind: .button { context.send(viewAction: .removeDummyPINCode) })
                } else {
                    ListRow(label: .plain(title: "Set Decoy PIN"),
                            kind: .button { context.send(viewAction: .changeDummyPINCode) })
                }
            } header: {
                Text("Decoy PIN (Duress Mode)")
            } footer: {
                Text("When the decoy PIN is entered, a fake chat list is shown. Only the real PIN reveals actual messages. Manage this from your real settings only.")
            }
        }
        .compoundList()
        .navigationTitle(L10n.commonScreenLock)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
    }
}

// MARK: - Previews

struct AppLockSetupSettingsScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = AppLockSetupSettingsScreenViewModel(appLockService: AppLockServiceMock.mock())
    static let dummyPINViewModel = AppLockSetupSettingsScreenViewModel(appLockService: AppLockServiceMock.mock(dummyPINCode: "1111"))
    
    static var previews: some View {
        NavigationStack {
            AppLockSetupSettingsScreen(context: viewModel.context)
        }
        .previewDisplayName("No Decoy PIN")
        
        NavigationStack {
            AppLockSetupSettingsScreen(context: dummyPINViewModel.context)
        }
        .previewDisplayName("With Decoy PIN")
    }
}
