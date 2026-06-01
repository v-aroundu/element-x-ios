//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct AppLockSetupDummyPINScreen: View {
    @ObservedObject var context: AppLockSetupDummyPINScreenViewModel.Context
    
    @FocusState private var textFieldFocus: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                header
                
                PINTextField(pinCode: $context.pinCode, isSecure: true)
                    .focused($textFieldFocus)
            }
            .padding(.horizontal, 16)
            .padding(.top, UIConstants.iconTopPaddingToNavigationBar)
            .frame(maxWidth: .infinity)
        }
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .toolbar { toolbar }
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .alert(item: $context.alertInfo)
        .onAppear { textFieldFocus = true }
    }
    
    private var header: some View {
        VStack(spacing: 8) {
            BigIcon(icon: \.lockSolid)
                .padding(.bottom, 8)
            
            Text(context.viewState.title)
                .font(.compound.headingMDBold)
                .multilineTextAlignment(.center)
                .foregroundColor(.compound.textPrimary)
            
            Text(context.viewState.subtitle)
                .font(.compound.bodyMD)
                .multilineTextAlignment(.center)
                .foregroundColor(.compound.textSecondary)
        }
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.actionCancel) {
                context.send(viewAction: .cancel)
            }
        }
    }
}

// MARK: - Previews

struct AppLockSetupDummyPINScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = AppLockSetupDummyPINScreenViewModel(appLockService: AppLockServiceMock.mock())
    
    static var previews: some View {
        NavigationStack {
            AppLockSetupDummyPINScreen(context: viewModel.context)
        }
    }
}
