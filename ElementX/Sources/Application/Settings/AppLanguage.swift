//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// The languages supported by the app.
/// Used only to open the iOS per-app language settings page.
enum AppLanguage: String, CaseIterable, Codable {
    case english = "en-US"
    case arabic = "ar"
}
