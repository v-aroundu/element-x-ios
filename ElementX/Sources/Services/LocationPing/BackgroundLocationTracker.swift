//
// BackgroundLocationTracker.swift
// ElementX
//
// Tracks device location in the background and sends pings to the AroundU backend.
// Logic mirrors the Flutter AppDelegate:
//   • Send immediately on first fix
//   • Send when the device moves ≥ 10 m since the last sent location
//   • Send after 5 minutes even when stationary
//

import CoreLocation
import Foundation
import UIKit

// MARK: - Protocol

protocol BackgroundLocationTrackerProtocol: AnyObject {
    var isTracking: Bool { get }
    func startTracking()
    func stopTracking()
}

// MARK: - Implementation

@MainActor
final class BackgroundLocationTracker: NSObject, BackgroundLocationTrackerProtocol {
    // MARK: - Config (mirrors Flutter AppDelegate)
    private let minimumDistanceMeters: Double = 10.0
    private let minimumTimeIntervalSeconds: TimeInterval = 300.0 // 5 minutes

    // MARK: - State
    private(set) var isTracking = false
    private var pendingStartAfterAuthorization = false
    private var lastSentLocation: CLLocation?
    private var lastSentDate: Date?
    private var isFirstLocation = true
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Dependencies
    private let pingService: LocationPingServiceProtocol
    private let locationManager: CLLocationManager

    init(pingService: LocationPingServiceProtocol) {
        self.pingService = pingService
        locationManager = CLLocationManager()
        super.init()
        configureLocationManager()
        registerAppStateObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        // Call UIApplication directly — cannot call @MainActor-isolated methods from deinit
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
    }

    // MARK: - BackgroundLocationTrackerProtocol

    func startTracking() {
        guard !isTracking else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            MXLog.warning("[BackgroundLocationTracker] Location services disabled")
            return
        }
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            MXLog.info("[BackgroundLocationTracker] Requesting authorization, will start after grant")
            pendingStartAfterAuthorization = true
            locationManager.requestAlwaysAuthorization()
            return
        }
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            MXLog.warning("[BackgroundLocationTracker] Missing location permission: \(status.rawValue)")
            return
        }
        activateTracking()
    }

    /// Internal — called once authorization is confirmed.
    private func activateTracking() {
        isTracking = true
        isFirstLocation = true
        lastSentLocation = nil
        lastSentDate = nil
        pendingStartAfterAuthorization = false

        // Mirror Flutter config — coarse accuracy is sufficient for periodic pings
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.activityType = .other
        locationManager.pausesLocationUpdatesAutomatically = false

        // Only set background-location flag after confirming authorization so we
        // never call this from an unauthorized or pre-authorization state, which
        // can cause a crash / UI freeze on some iOS versions.
        if locationManager.authorizationStatus == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = false
        }

        locationManager.startMonitoringSignificantLocationChanges()
        locationManager.startUpdatingLocation()
        startBackgroundTask()

        MXLog.info("[BackgroundLocationTracker] Tracking started (auth: \(locationManager.authorizationStatus.rawValue))")
    }

    func stopTracking() {
        pendingStartAfterAuthorization = false
        guard isTracking else { return }
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        if locationManager.authorizationStatus == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = false
        }
        locationManager.pausesLocationUpdatesAutomatically = true
        isTracking = false
        isFirstLocation = true
        lastSentLocation = nil
        lastSentDate = nil
        endBackgroundTask()
        MXLog.info("[BackgroundLocationTracker] Tracking stopped")
    }

    // MARK: - Private

    private func configureLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.activityType = .other
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    private func registerAppStateObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
    }

    @objc private func appDidEnterBackground() {
        if isTracking { startBackgroundTask() }
    }

    @objc private func appWillEnterForeground() {
        endBackgroundTask()
    }

    private func startBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func shouldSend(location: CLLocation) -> Bool {
        // Reject stale locations (> 15 s old)
        guard abs(location.timestamp.timeIntervalSinceNow) <= 15 else {
            MXLog.info("[BackgroundLocationTracker] Skipping stale location")
            return false
        }
        // Reject invalid accuracy
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 150 else {
            MXLog.info("[BackgroundLocationTracker] Skipping low-accuracy location: \(Int(location.horizontalAccuracy))m")
            return false
        }
        // Always send the first fix
        if isFirstLocation { return true }

        let now = Date()
        if let last = lastSentDate, now.timeIntervalSince(last) >= minimumTimeIntervalSeconds {
            MXLog.info("[BackgroundLocationTracker] Time threshold met — sending")
            return true
        }
        if let lastLoc = lastSentLocation, location.distance(from: lastLoc) >= minimumDistanceMeters {
            MXLog.info("[BackgroundLocationTracker] Distance threshold met — sending")
            return true
        }
        return false
    }
}

// MARK: - CLLocationManagerDelegate

extension BackgroundLocationTracker: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            guard self.isTracking else { return }
            guard self.shouldSend(location: location) else { return }

            // Temporarily bump accuracy for time-based updates
            if let last = self.lastSentDate, Date().timeIntervalSince(last) >= self.minimumTimeIntervalSeconds {
                manager.desiredAccuracy = kCLLocationAccuracyBest
            }

            self.isFirstLocation = false
            self.lastSentLocation = location
            self.lastSentDate = Date()

            let result = await self.pingService.sendPing(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy,
                sourceTimestamp: location.timestamp
            )

            switch result {
            case .success:
                MXLog.info("[BackgroundLocationTracker] Ping sent — lat:\(location.coordinate.latitude) lon:\(location.coordinate.longitude)")
            case .failure(let error):
                MXLog.error("[BackgroundLocationTracker] Ping failed: \(error)")
            }

            // Reset accuracy back to coarse for battery efficiency
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

            // Keep background task alive
            if !UIApplication.shared.isActive { self.startBackgroundTask() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MXLog.error("[BackgroundLocationTracker] Location error: \(error.localizedDescription)")
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            MXLog.info("[BackgroundLocationTracker] Auth changed: \(status.rawValue)")
            switch status {
            case .denied, .restricted:
                self.pendingStartAfterAuthorization = false
                self.stopTracking()
            case .authorizedAlways:
                // Upgrade background updates if we're already tracking with WhenInUse
                if self.isTracking, !manager.allowsBackgroundLocationUpdates {
                    manager.allowsBackgroundLocationUpdates = true
                    manager.showsBackgroundLocationIndicator = false
                    MXLog.info("[BackgroundLocationTracker] Upgraded to always-on background updates")
                }
                // Start if we were waiting for authorization
                if self.pendingStartAfterAuthorization {
                    self.activateTracking()
                }
            case .authorizedWhenInUse:
                // Start (without background updates) if we were waiting for authorization
                if self.pendingStartAfterAuthorization {
                    self.activateTracking()
                }
            default:
                break
            }
        }
    }
}

private extension UIApplication {
    var isActive: Bool { applicationState == .active }
}
