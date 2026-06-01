//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import MatrixRustSDK
import SwiftUI

typealias EncryptionResetScreenViewModelType = StateStoreViewModelV2<EncryptionResetScreenViewState, EncryptionResetScreenViewAction>

class EncryptionResetScreenViewModel: EncryptionResetScreenViewModelType, EncryptionResetScreenViewModelProtocol {
    private let clientProxy: ClientProxyProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    
    private let actionsSubject: PassthroughSubject<EncryptionResetScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<EncryptionResetScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    private var identityResetHandle: IdentityResetHandle?
    private var passwordCancellable: AnyCancellable?

    init(clientProxy: ClientProxyProtocol, userIndicatorController: UserIndicatorControllerProtocol) {
        self.clientProxy = clientProxy
        self.userIndicatorController = userIndicatorController
        
        super.init(initialViewState: EncryptionResetScreenViewState(bindings: .init()))
    }
    
    // MARK: - Public
    
    override func process(viewAction: EncryptionResetScreenViewAction) {
        switch viewAction {
        case .reset:
            state.bindings.alertInfo = .init(id: UUID(),
                                             title: L10n.screenResetEncryptionConfirmationAlertTitle,
                                             message: L10n.screenResetEncryptionConfirmationAlertSubtitle,
                                             primaryButton: .init(title: L10n.screenResetEncryptionConfirmationAlertAction, role: .destructive) { [weak self] in
                                                 guard let self else { return }
                                                 Task { await self.startResetFlow() }
                                             })
        case .cancel:
            actionsSubject.send(.cancel)
        case .openOIDCURL:
            guard let url = state.oidcApprovalURL else { return }
            actionsSubject.send(.openURL(url))
        case .continueAfterOIDCApproval:
            Task { await resetWithOIDCAuthorisation() }
        }
    }
    
    func stop() {
        Task {
            await identityResetHandle?.cancel()
        }
    }
    
    // MARK: - Private
    
    private func startResetFlow() async {
        showLoadingIndicator()
        
        switch await clientProxy.resetIdentity() {
        case .success(let handle):
            // If the handle is missing then interactive authentication wasn't
            // necessary and the reset proceeded as normal
            guard let handle else {
                hideLoadingIndicator()
                actionsSubject.send(.resetFinished)
                return
            }
            
            identityResetHandle = handle
            
            switch handle.authType() {
            case .uiaa:
                // Homeserver supports password-based UIAA — show the password entry screen.
                let passwordPublisher = PassthroughSubject<String, Never>()
                passwordCancellable = passwordPublisher.sink { [weak self] password in
                    guard let self else { return }
                    passwordCancellable = nil
                    Task { await self.resetWith(password: password) }
                }
                
                // Hide the loading indicator before navigating to the password screen
                // so the persistent modal does not block the pushed screen.
                hideLoadingIndicator()
                actionsSubject.send(.requestPassword(passwordPublisher: passwordPublisher))
                
            case .oidc(let info):
                // Homeserver requires OIDC approval. Show the in-app "open browser" UI.
                // The user opens the approval URL, approves in the browser, then comes back
                // and taps "Continue" which triggers .continueAfterOIDCApproval.
                guard let approvalURL = URL(string: info.approvalUrl) else {
                    MXLog.error("Invalid OIDC approval URL: \(info.approvalUrl)")
                    hideLoadingIndicator()
                    showErrorToast()
                    return
                }
                
                hideLoadingIndicator()
                state.oidcApprovalURL = approvalURL
            }
        case .failure(let error):
            MXLog.error("Failed resetting encryption with error \(error)")
            hideLoadingIndicator()
            showErrorToast()
        }
    }
    
    func resetWith(password: String) async {
        guard let identityResetHandle else {
            fatalError("Requested reset flow continuation without a stored handle")
        }
        
        showLoadingIndicator()
        
        do {
            try await identityResetHandle.reset(auth: .password(passwordDetails: .init(identifier: clientProxy.userID, password: password)))
            hideLoadingIndicator()
            actionsSubject.send(.resetFinished)
        } catch {
            MXLog.error("Failed resetting encryption with error \(error)")
            hideLoadingIndicator()
            showErrorToast()
        }
    }
    
    private func resetWithOIDCAuthorisation() async {
        guard let identityResetHandle else {
            fatalError("Requested reset flow continuation without a stored handle")
        }
        
        showLoadingIndicator()
        
        do {
            try await identityResetHandle.reset(auth: nil)
            hideLoadingIndicator()
            actionsSubject.send(.resetFinished)
        } catch {
            MXLog.error("Failed resetting encryption after OIDC approval with error \(error)")
            hideLoadingIndicator()
            showErrorToast()
        }
    }
    
    // MARK: Toasts and loading indicators
    
    private static let loadingIndicatorIdentifier = "\(EncryptionResetScreenViewModel.self)-Loading"
    
    private func showLoadingIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(id: Self.loadingIndicatorIdentifier,
                                                              type: .modal,
                                                              title: L10n.commonLoading,
                                                              persistent: true))
    }
    
    private func hideLoadingIndicator() {
        userIndicatorController.retractIndicatorWithId(Self.loadingIndicatorIdentifier)
    }
    
    private func showErrorToast() {
        userIndicatorController.submitIndicator(UserIndicator(title: L10n.errorUnknown))
    }
}
