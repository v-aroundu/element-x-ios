//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

enum AppLockPromptScreenCoordinatorAction {
    /// The user chose to enable app lock.
    case enableAppLock
    /// The user skipped the prompt.
    case skip
}

final class AppLockPromptScreenCoordinator: CoordinatorProtocol {
    private var viewModel: AppLockPromptScreenViewModelProtocol
    private let actionsSubject: PassthroughSubject<AppLockPromptScreenCoordinatorAction, Never> = .init()
    private var cancellables = Set<AnyCancellable>()
    
    var actions: AnyPublisher<AppLockPromptScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init() {
        viewModel = AppLockPromptScreenViewModel()
    }
    
    func start() {
        viewModel.actions.sink { [weak self] action in
            MXLog.info("Coordinator: received view model action: \(action)")
            
            guard let self else { return }
            switch action {
            case .enableAppLock:
                actionsSubject.send(.enableAppLock)
            case .skip:
                actionsSubject.send(.skip)
            }
        }
        .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(AppLockPromptScreen(context: viewModel.context))
    }
}
