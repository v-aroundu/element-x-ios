//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

/// Coordinator that wraps `DummyHomeScreen`.
/// Displayed when the user enters their duress (dummy) PIN.
final class DummyHomeScreenCoordinator: CoordinatorProtocol {
    func toPresentable() -> AnyView {
        AnyView(DummyHomeScreen())
    }
}
