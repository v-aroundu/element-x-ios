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

enum AppLockFlowCoordinatorAction: Equatable {
    /// Display the unlock flow.
    case lockApp
    /// Hide the unlock flow and show real chats.
    case unlockApp
    /// Hide the unlock flow and show the decoy (dummy) chats.
    case unlockAppWithDummyPIN
    /// Forces a logout of the user.
    case forceLogout
}

/// Coordinates the display of any screens shown when the app is locked.
class AppLockFlowCoordinator: CoordinatorProtocol {
    let appLockService: AppLockServiceProtocol
    let navigationCoordinator: NavigationRootCoordinator
    let appSettings: AppSettings
    
    /// States the flow can find itself in
    enum State: StateType {
        case initial
        case unlocked
        case appObscured
        case backgrounded
        case launching
        case attemptingPINUnlock
        case loggingOut
    }

    /// Events that can be triggered on the flow state machine
    enum Event: EventType {
        case start
        case willResignActive
        case didEnterBackground
        case willEnterForeground
        case didBecomeActive
        case didUnlockWithPIN
        case didUnlockWithDummyPIN
        case forceLogout
        case serviceEnabled
        case serviceDisabled
    }
    
    private let stateMachine: StateMachine<State, Event>
    
    private var cancellables: Set<AnyCancellable> = []
    
    private let actionsSubject: PassthroughSubject<AppLockFlowCoordinatorAction, Never> = .init()
    var actions: AnyPublisher<AppLockFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(initialState: State = .initial,
         appLockService: AppLockServiceProtocol,
         navigationCoordinator: NavigationRootCoordinator,
         notificationCenter: NotificationCenter = .default,
         appSettings: AppSettings) {
        self.appLockService = appLockService
        self.navigationCoordinator = navigationCoordinator
        self.appSettings = appSettings
        
        stateMachine = .init(state: initialState)
        configureStateMachine()
        
        notificationCenter.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.stateMachine.tryEvent(.willResignActive) }
            .store(in: &cancellables)
        
        notificationCenter.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.stateMachine.tryEvent(.didEnterBackground) }
            .store(in: &cancellables)
        
        notificationCenter.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.stateMachine.tryEvent(.willEnterForeground) }
            .store(in: &cancellables)
        
        notificationCenter.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.stateMachine.tryEvent(.didBecomeActive) }
            .store(in: &cancellables)
        
        appLockService.isEnabledPublisher
            .sink { [weak self] isEnabled in
                self?.stateMachine.tryEvent(isEnabled ? .serviceEnabled : .serviceDisabled)
            }
            .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(navigationCoordinator.toPresentable())
    }
    
    // MARK: - State machine
    
    private func configureStateMachine() {
        stateMachine.addRouteMapping { [weak self] event, fromState, _ in
            guard let self, appLockService.isEnabled else { return fromState }
            
            switch (fromState, event) {
            case (.initial, .start):
                return .backgrounded
            
            case (.unlocked, .willResignActive):
                return .appObscured
            case (.appObscured, .didBecomeActive):
                return .unlocked
            case (_, .didEnterBackground):
                return .backgrounded
            case (_, .willEnterForeground):
                return .launching
            case (.launching, .didBecomeActive):
                guard appLockService.computeNeedsUnlock(didBecomeActiveAt: .now) else { return .unlocked }
                return .attemptingPINUnlock
            case (.attemptingPINUnlock, .didUnlockWithPIN):
                return .unlocked
            case (.attemptingPINUnlock, .didUnlockWithDummyPIN):
                return .unlocked // State machine stays in "unlocked" — AppCoordinator handles the dummy session swap
            case (.attemptingPINUnlock, .forceLogout):
                return .loggingOut
            
            // Transition to a valid state when enabling the service for the first time.
            case (.initial, .serviceEnabled):
                return .unlocked
            // Transition to a valid state once the service is disabled following a forced logout.
            case (.loggingOut, .serviceDisabled):
                return .unlocked
            
            default:
                return fromState
            }
        }
        
        stateMachine.addAnyHandler(.any => .any) { [weak self] context in
            guard let self, context.fromState != context.toState else { return }
            
            MXLog.info("Transitioning from `\(context.fromState)` to `\(context.toState)` with event `\(String(describing: context.event))`.")
            
            switch (context.fromState, context.toState) {
            case (_, .appObscured):
                showPlaceholder()
            case (_, .backgrounded):
                appLockService.applicationDidEnterBackground()
                showPlaceholder() // Double call but just to be safe. Useful at app launch.
            case (_, .launching):
                showPlaceholder() // Triple call but necessary after being suspended.
            case (_, .attemptingPINUnlock):
                showUnlockScreen()
            case (_, .unlocked):
                if context.event == .didUnlockWithDummyPIN {
                    actionsSubject.send(.unlockAppWithDummyPIN)
                } else {
                    actionsSubject.send(.unlockApp)
                }
            case (_, .loggingOut):
                actionsSubject.send(.forceLogout)
            default:
                fatalError("Unhandled transition.")
            }
        }
        
        stateMachine.addErrorHandler { context in
            fatalError("Unexpected transition from `\(context.fromState)` to `\(context.toState)` with event `\(String(describing: context.event))`.")
        }
        
        stateMachine.tryEvent(.start)
    }
    
    // MARK: - App unlock
    
    /// Displays the unlock flow with the app's placeholder view to hide obscure the view hierarchy in the app switcher.
    private func showPlaceholder() {
        navigationCoordinator.setRootCoordinator(PlaceholderScreenCoordinator(hideBrandChrome: appSettings.hideBrandChrome, hideGradientBackground: false), animated: false)
        actionsSubject.send(.lockApp)
    }
    
    /// Displays the unlock flow with the main unlock screen.
    private func showUnlockScreen() {
        let coordinator = AppLockScreenCoordinator(parameters: .init(appLockService: appLockService))
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .appUnlocked:
                stateMachine.tryEvent(.didUnlockWithPIN)
            case .appUnlockedWithDummyPIN:
                stateMachine.tryEvent(.didUnlockWithDummyPIN)
            case .forceLogout:
                stateMachine.tryEvent(.forceLogout)
            }
        }
        .store(in: &cancellables)
        
        navigationCoordinator.setRootCoordinator(coordinator, animated: false)
        actionsSubject.send(.lockApp)
    }
}
