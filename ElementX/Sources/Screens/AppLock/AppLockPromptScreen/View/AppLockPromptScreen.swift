//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SFSafeSymbols
import SwiftUI

/// A modal sheet prompting the user to enable App Lock for security after login.
struct AppLockPromptScreen: View {
    @ObservedObject var context: AppLockPromptScreenViewModel.Context
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                buttons
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }
    
    // MARK: - Private
    
    private var header: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.compound.bgSubtlePrimary)
                    .frame(width: 80, height: 80)
                
                Image(systemSymbol: .lockShieldFill)
                    .font(.system(size: 36))
                    .foregroundColor(.compound.iconPrimary)
            }
            .padding(.bottom, 8)
            
            Text(context.viewState.title)
                .font(.compound.headingLGBold)
                .multilineTextAlignment(.center)
                .foregroundColor(.compound.textPrimary)
            
            Text(context.viewState.subtitle)
                .font(.compound.bodyMD)
                .multilineTextAlignment(.center)
                .foregroundColor(.compound.textSecondary)
        }
    }
    
    private var buttons: some View {
        VStack(spacing: 16) {
            Button(L10n.screenAppLockPromptEnable) {
                context.send(viewAction: .enable)
            }
            .buttonStyle(.compound(.primary))
            .accessibilityIdentifier(A11yIdentifiers.appLockPromptScreen.enable)
            
            Button {
                context.send(viewAction: .skip)
            } label: {
                Text(L10n.screenAppLockPromptSkip)
                    .font(.compound.bodyLGSemibold)
                    .foregroundColor(.compound.textSecondary)
                    .padding(14)
            }
            .accessibilityIdentifier(A11yIdentifiers.appLockPromptScreen.skip)
        }
    }
}

// MARK: - Previews

struct AppLockPromptScreen_Previews: PreviewProvider {
    static let viewModel = AppLockPromptScreenViewModel()
    
    static var previews: some View {
        AppLockPromptScreen(context: viewModel.context)
    }
}
