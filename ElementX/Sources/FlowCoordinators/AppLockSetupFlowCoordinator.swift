//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftState
import SwiftUI

enum AppLockSetupFlowCoordinatorAction: Equatable {
    /// The flow is complete.
    case complete
    /// The user failed to remember their existing PIN.
    case forceLogout
}

/// Coordinates the display of any screens used to configure the App Lock feature.
class AppLockSetupFlowCoordinator: FlowCoordinatorProtocol {
    private let presentingFlow: PresentationFlow
    private let appLockService: AppLockServiceProtocol
    private let navigationStackCoordinator: NavigationStackCoordinator
    private let modalNavigationStackCoordinator = NavigationStackCoordinator()
    
    /// The presentation context of the flow.
    enum PresentationFlow {
        /// The flow is shown for mandatory PIN creation in the authentication flow or on app launch.
        case onboarding
        /// The flow is shown from the Settings screen.
        case settings
    }
    
    /// States the flow can find itself in
    enum State: StateType {
        case initial
        case unlock
        case createPIN(replacingExitingPIN: Bool)
        case settings
        case complete
        case loggingOut
    }

    /// Events that can be triggered on the flow state machine
    enum Event: EventType {
        case start
        case pinEntered
        case changePIN
        case appLockDisabled
        case cancel
        case forceLogout
    }
    
    private let stateMachine: StateMachine<State, Event>
    private var cancellables: Set<AnyCancellable> = []
    
    private let actionsSubject: PassthroughSubject<AppLockSetupFlowCoordinatorAction, Never> = .init()
    var actions: AnyPublisher<AppLockSetupFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(presentingFlow: PresentationFlow, appLockService: AppLockServiceProtocol, navigationStackCoordinator: NavigationStackCoordinator) {
        self.presentingFlow = presentingFlow
        self.appLockService = appLockService
        self.navigationStackCoordinator = navigationStackCoordinator
        
        stateMachine = .init(state: .initial)
        configureStateMachine()
    }
    
    func start(animated: Bool) {
        stateMachine.tryEvent(.start)
    }
    
    func handleAppRoute(_ appRoute: AppRoute, animated: Bool) { }
    func clearRoute(animated: Bool) { }
    
    // MARK: - Private
    
    private func configureStateMachine() {
        stateMachine.addRouteMapping { [weak self] event, fromState, _ in
            guard let self else { return nil }
            
            switch (fromState, event) {
            case (.initial, .start):
                if presentingFlow == .onboarding { return .createPIN(replacingExitingPIN: false) }
                return appLockService.isEnabled ? .unlock : .createPIN(replacingExitingPIN: false)
            case (.unlock, .pinEntered):
                return .settings
            case (.unlock, .cancel):
                return .complete
            case (.unlock, .forceLogout):
                return .loggingOut
            case (.createPIN(let replacingExitingPIN), .pinEntered):
                if presentingFlow == .onboarding {
                    return .complete
                } else if !replacingExitingPIN {
                    return .settings
                } else {
                    return .settings
                }
            case (.createPIN(let replacingExitingPIN), .cancel):
                return replacingExitingPIN ? .settings : .complete
            case (.settings, .changePIN):
                return .createPIN(replacingExitingPIN: true)
            case (.settings, .appLockDisabled):
                return .complete
            default:
                return nil
            }
        }
        
        stateMachine.addAnyHandler(.any => .any) { [weak self] context in
            guard let self else { return }
            
            MXLog.info("Transitioning from `\(context.fromState)` to `\(context.toState)` with event `\(String(describing: context.event))`.")
            switch (context.fromState, context.toState) {
            case (.initial, .unlock):
                showPINUnlock()
            case (.initial, .createPIN):
                showCreatePIN()
            case (.unlock, .settings):
                showSettings()
            case (.createPIN(let replacingExitingPIN), .settings):
                if replacingExitingPIN {
                    navigationStackCoordinator.setSheetCoordinator(nil)
                } else {
                    showSettings()
                }
            case (.settings, .createPIN):
                showCreatePIN()
            case (_, .complete):
                complete(from: context.fromState)
            case (.unlock, .loggingOut):
                actionsSubject.send(.forceLogout)
            default:
                fatalError("Unhandled transition.")
            }
        }
        
        stateMachine.addErrorHandler { context in
            fatalError("Unexpected transition from `\(context.fromState)` to `\(context.toState)` with event `\(String(describing: context.event))`.")
        }
    }

    private func showCreatePIN() {
        let isMandatory = presentingFlow == .onboarding
        
        let coordinator = AppLockSetupPINScreenCoordinator(parameters: .init(initialMode: .create,
                                                                             isMandatory: isMandatory,
                                                                             appLockService: appLockService))
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .complete:
                stateMachine.tryEvent(.pinEntered)
            case .cancel:
                stateMachine.tryEvent(.cancel)
            case .forceLogout:
                fatalError("Creating a PIN can't force a logout.")
            }
        }
        .store(in: &cancellables)
        
        if presentingFlow == .onboarding {
            if navigationStackCoordinator.rootCoordinator == nil {
                navigationStackCoordinator.setRootCoordinator(coordinator)
            } else {
                navigationStackCoordinator.push(coordinator)
            }
        } else {
            modalNavigationStackCoordinator.setRootCoordinator(coordinator)
            navigationStackCoordinator.setSheetCoordinator(modalNavigationStackCoordinator)
        }
    }
    
    private func showPINUnlock() {
        let coordinator = AppLockSetupPINScreenCoordinator(parameters: .init(initialMode: .unlock,
                                                                             isMandatory: false,
                                                                             appLockService: appLockService))
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .complete:
                stateMachine.tryEvent(.pinEntered)
            case .cancel:
                stateMachine.tryEvent(.cancel)
            case .forceLogout:
                stateMachine.tryEvent(.forceLogout)
            }
        }
        .store(in: &cancellables)
        modalNavigationStackCoordinator.setRootCoordinator(coordinator)
        navigationStackCoordinator.setSheetCoordinator(modalNavigationStackCoordinator)
    }
    
    private func showSettings() {
        let coordinator = AppLockSetupSettingsScreenCoordinator(parameters: .init(appLockService: appLockService))
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .changePINCode:
                stateMachine.tryEvent(.changePIN)
            case .appLockDisabled:
                stateMachine.tryEvent(.appLockDisabled)
            case .changeDummyPINCode:
                showDummyPINSetup()
            }
        }
        .store(in: &cancellables)
        
        navigationStackCoordinator.push(coordinator, animated: false) { [weak self] in
            self?.actionsSubject.send(.complete)
        }
        navigationStackCoordinator.setSheetCoordinator(nil)
    }
    
    private func showDummyPINSetup() {
        let dummyPINCoordinator = AppLockSetupDummyPINScreenCoordinator(parameters: .init(appLockService: appLockService))
        dummyPINCoordinator.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .complete, .cancel:
                navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        dummyPINCoordinator.start()
        let sheetNav = NavigationStackCoordinator()
        sheetNav.setRootCoordinator(dummyPINCoordinator)
        navigationStackCoordinator.setSheetCoordinator(sheetNav)
    }
    
    private func complete(from state: State) {
        switch state {
        case .initial, .complete, .loggingOut: fatalError()
        case .unlock:
            navigationStackCoordinator.setSheetCoordinator(nil)
            actionsSubject.send(.complete)
        case .createPIN:
            navigationStackCoordinator.setSheetCoordinator(nil)
            actionsSubject.send(.complete)
        case .settings:
            navigationStackCoordinator.pop()
            actionsSubject.send(.complete)
        }
    }
}
