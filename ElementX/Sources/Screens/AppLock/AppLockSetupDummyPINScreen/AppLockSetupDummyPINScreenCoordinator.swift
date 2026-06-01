//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct AppLockSetupDummyPINScreenCoordinatorParameters {
    let appLockService: AppLockServiceProtocol
}

enum AppLockSetupDummyPINScreenCoordinatorAction {
    case complete
    case cancel
}

/// Coordinator that presents a 2-step PIN entry screen for configuring the Dummy (Duress) PIN.
final class AppLockSetupDummyPINScreenCoordinator: CoordinatorProtocol {
    private let parameters: AppLockSetupDummyPINScreenCoordinatorParameters
    private let actionsSubject: PassthroughSubject<AppLockSetupDummyPINScreenCoordinatorAction, Never> = .init()
    private var cancellables = Set<AnyCancellable>()
    
    private var viewModel: AppLockSetupDummyPINScreenViewModel?
    
    var actions: AnyPublisher<AppLockSetupDummyPINScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: AppLockSetupDummyPINScreenCoordinatorParameters) {
        self.parameters = parameters
    }
    
    func start() {
        let vm = AppLockSetupDummyPINScreenViewModel(appLockService: parameters.appLockService)
        vm.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .complete:
                actionsSubject.send(.complete)
            case .cancel:
                actionsSubject.send(.cancel)
            }
        }
        .store(in: &cancellables)
        viewModel = vm
    }
    
    func toPresentable() -> AnyView {
        guard let viewModel else { fatalError("Call start() before toPresentable()") }
        return AnyView(AppLockSetupDummyPINScreen(context: viewModel.context))
    }
}
