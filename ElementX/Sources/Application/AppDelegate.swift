//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import FirebaseMessaging
import SwiftUI
import Firebase
import FirebaseCrashlytics

enum AppDelegateCallback {
    case registeredNotifications(deviceToken: Data)
    case failedToRegisteredNotifications(error: Error)
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    let callbacks = PassthroughSubject<AppDelegateCallback, Never>()
    var orientationLock = UIInterfaceOrientationMask.all
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Add waita SceneDelegate to the SwiftUI scene so that we can connect up the WindowManager.
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AppTheme.apply()
        FirebaseApp.configure()
        
        // Enable Crashlytics data collection unconditionally.
        // Without this, crash reports are NOT uploaded to Firebase.
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        
        // Log a non-fatal breadcrumb so we can confirm reports are arriving in the console.
        Crashlytics.crashlytics().log("App launched — Crashlytics collection enabled.")
        
        NSTextAttachment.registerViewProviderClass(PillAttachmentViewProvider.self, forFileType: InfoPlistReader.main.pillsUTType)
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Forward the APNs token to Firebase so FCM and Crashlytics work correctly.
        Messaging.messaging().apnsToken = deviceToken
        callbacks.send(.registeredNotifications(deviceToken: deviceToken))
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        callbacks.send(.failedToRegisteredNotifications(error: error))
    }
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        orientationLock
    }
}
