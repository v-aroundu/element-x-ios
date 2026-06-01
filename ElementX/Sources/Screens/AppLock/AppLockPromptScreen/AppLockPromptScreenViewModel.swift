//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias AppLockPromptScreenViewModelType = StateStoreViewModel<AppLockPromptScreenViewState, AppLockPromptScreenViewAction>

class AppLockPromptScreenViewModel: AppLockPromptScreenViewModelType, AppLockPromptScreenViewModelProtocol {
    private var actionsSubject: PassthroughSubject<AppLockPromptScreenViewModelAction, Never> = .init()
    
    var actions: AnyPublisher<AppLockPromptScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init() {
        super.init(initialViewState: AppLockPromptScreenViewState())
    }
    
    // MARK: - Public
    
    override func process(viewAction: AppLockPromptScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .enable:
            actionsSubject.send(.enableAppLock)
        case .skip:
            actionsSubject.send(.skip)
        }
    }
}
