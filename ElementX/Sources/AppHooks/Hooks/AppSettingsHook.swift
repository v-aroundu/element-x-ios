//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

protocol AppSettingsHookProtocol {
    func configure(_ appSettings: AppSettings) -> AppSettings
}

struct DefaultAppSettingsHook: AppSettingsHookProtocol {
    func configure(_ appSettings: AppSettings) -> AppSettings {
        // Lock the app to the aroundU Messenger homeserver so that tapping "Sign in"
        // goes directly to the username/password screen without any server selection step.
        appSettings.override(accountProviders: ["messenger.aroundu.app"],
                             allowOtherAccountProviders: false,
                             hideBrandChrome: appSettings.hideBrandChrome,
                             pushGatewayBaseURL: appSettings.pushGatewayBaseURL,
                             oidcRedirectURL: appSettings.oidcRedirectURL,
                             websiteURL: appSettings.websiteURL,
                             logoURL: appSettings.logoURL,
                             copyrightURL: appSettings.copyrightURL,
                             acceptableUseURL: appSettings.acceptableUseURL,
                             privacyURL: appSettings.privacyURL,
                             encryptionURL: appSettings.encryptionURL,
                             deviceVerificationURL: appSettings.deviceVerificationURL,
                             chatBackupDetailsURL: appSettings.chatBackupDetailsURL,
                             identityPinningViolationDetailsURL: appSettings.identityPinningViolationDetailsURL,
                             historySharingDetailsURL: appSettings.historySharingDetailsURL,
                             elementWebHosts: appSettings.elementWebHosts,
                             accountProvisioningHost: appSettings.accountProvisioningHost,
                             bugReportApplicationID: appSettings.bugReportApplicationID,
                             analyticsTermsURL: appSettings.analyticsTermsURL,
                             mapTilerConfiguration: appSettings.mapTilerConfiguration)
        return appSettings
    }
}
