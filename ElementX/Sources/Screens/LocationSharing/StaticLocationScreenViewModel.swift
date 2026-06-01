//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import CoreLocation
import Foundation

typealias StaticLocationScreenViewModelType = StateStoreViewModelV2<StaticLocationScreenViewState, StaticLocationScreenViewAction>

class StaticLocationScreenViewModel: StaticLocationScreenViewModelType, StaticLocationScreenViewModelProtocol {
    private let timelineController: TimelineControllerProtocol
    private let locationPingService: LocationPingServiceProtocol?
    private let analytics: AnalyticsService
    private let userIndicatorController: UserIndicatorControllerProtocol
    
    /// Repeating task that fires pings every 5 seconds during a live session
    private var liveLocationTask: Task<Void, Never>?
    private let liveLocationInterval: Duration = .seconds(240) // 4 minutes
    
    private let actionsSubject: PassthroughSubject<StaticLocationScreenViewModelAction, Never> = .init()
    var actions: AnyPublisher<StaticLocationScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    deinit {
        liveLocationTask?.cancel()
    }
    
    init(interactionMode: StaticLocationInteractionMode,
         mapURLBuilder: MapTilerURLBuilderProtocol,
         timelineController: TimelineControllerProtocol,
         locationPingService: LocationPingServiceProtocol? = nil,
         analytics: AnalyticsService,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.timelineController = timelineController
        self.locationPingService = locationPingService
        self.analytics = analytics
        self.userIndicatorController = userIndicatorController
        
        super.init(initialViewState: .init(interactionMode: interactionMode, mapURLBuilder: mapURLBuilder))
    }
    
    override func process(viewAction: StaticLocationScreenViewAction) {
        switch viewAction {
        case .close:
            stopLiveLocationSession()
            actionsSubject.send(.close)
        case .selectLocation:
            guard let coordinate = state.bindings.mapCenterLocation else { return }
            let uncertainty = state.isSharingUserLocation ? context.geolocationUncertainty : nil
            Task { await sendLocation(.init(coordinate: coordinate, uncertainty: uncertainty), isUserLocation: state.isSharingUserLocation) }
        case .shareLiveLocation:
            guard state.bindings.isLocationAuthorized == true else {
                let action: () -> Void = { [weak self] in self?.actionsSubject.send(.openSystemSettings) }
                state.bindings.alertInfo = .init(locationSharingViewError: .missingAuthorization,
                                                 primaryButton: .init(title: L10n.actionNotNow, role: .cancel, action: nil),
                                                 secondaryButton: .init(title: L10n.commonSettings, action: action))
                return
            }
            // Only update the mode if it's not already following — avoids a map flicker
            if state.bindings.showsUserLocationMode != .showAndFollow {
                state.bindings.showsUserLocationMode = .showAndFollow
            }
            Task { await startLiveLocationSession() }
        case .stopLiveLocation:
            stopLiveLocationSession()
            actionsSubject.send(.close)
        case .userDidPan:
            state.bindings.showsUserLocationMode = .show
        case .centerToUser:
            switch state.bindings.isLocationAuthorized {
            case .some(true), .none:
                state.bindings.showsUserLocationMode = .showAndFollow
            case .some(false):
                let action: () -> Void = { [weak self] in self?.actionsSubject.send(.openSystemSettings) }
                state.bindings.alertInfo = .init(locationSharingViewError: .missingAuthorization,
                                                 primaryButton: .init(title: L10n.actionNotNow, role: .cancel, action: nil),
                                                 secondaryButton: .init(title: L10n.commonSettings, action: action))
            }
        }
    }
    
    // MARK: - Private
    
    private func sendLocation(_ geoURI: GeoURI, isUserLocation: Bool) async {
        guard case .success = await timelineController.sendLocation(body: geoURI.bodyMessage,
                                                                    geoURI: geoURI,
                                                                    description: nil,
                                                                    zoomLevel: 15,
                                                                    assetType: isUserLocation ? .sender : .pin) else {
            showErrorIndicator()
            return
        }
        
        actionsSubject.send(.close)
        
        analytics.trackComposer(inThread: false,
                                isEditing: false,
                                isReply: false,
                                messageType: isUserLocation ? .LocationUser : .LocationPin,
                                startsThread: nil)
    }
    
    private func showErrorIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(id: statusIndicatorID,
                                                              type: .toast,
                                                              title: L10n.errorUnknown,
                                                              iconName: "xmark"))
    }
    
    private var statusIndicatorID: String {
        "\(Self.self)-Status"
    }
    
    // MARK: - Live Location
    
    private func startLiveLocationSession() async {
        guard let pingService = locationPingService else {
            MXLog.warning("[LocationPingService] No ping service available, live location disabled")
            return
        }
        
        // Require a known coordinate before starting
        guard let coordinate = state.bindings.mapCenterLocation else {
            MXLog.warning("[LocationPingService] Location not yet available, cannot start live session")
            showErrorIndicator()
            return
        }
        
        let accuracy = state.bindings.geolocationUncertainty ?? 0.0
        let geoURI = GeoURI(latitude: coordinate.latitude, longitude: coordinate.longitude, uncertainty: accuracy)
        
        // Send an initial Matrix location event to the room
        guard case .success = await timelineController.sendLocation(body: geoURI.bodyMessage,
                                                                    geoURI: geoURI,
                                                                    description: nil,
                                                                    zoomLevel: 15,
                                                                    assetType: .sender) else {
            showErrorIndicator()
            return
        }
        
        analytics.trackComposer(inThread: false,
                                isEditing: false,
                                isReply: false,
                                messageType: .LocationUser,
                                startsThread: nil)
        
        liveLocationTask?.cancel()
        state.isLiveLocationActive = true
        
        // Show a persistent "Live location active" indicator
        userIndicatorController.submitIndicator(UserIndicator(id: liveIndicatorID,
                                                              type: .toast,
                                                              title: "Live location started",
                                                              iconName: "location.fill",
                                                              persistent: false))
        
        liveLocationTask = Task { [weak self] in
            guard let self else { return }
            // Ping immediately, then repeat on interval
            await self.pingCurrentLocation(using: pingService)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: self.liveLocationInterval)
                } catch {
                    break // task was cancelled
                }
                guard !Task.isCancelled else { break }
                await self.pingCurrentLocation(using: pingService)
            }
        }
        
        MXLog.info("[LocationPingService] Live location session started")
    }
    
    private func stopLiveLocationSession() {
        guard state.isLiveLocationActive else { return }
        liveLocationTask?.cancel()
        liveLocationTask = nil
        state.isLiveLocationActive = false
        userIndicatorController.retractIndicatorWithId(liveIndicatorID)
        MXLog.info("[LocationPingService] Live location session stopped")
    }
    
    private var liveIndicatorID: String {
        "\(Self.self)-LiveLocation"
    }
    
    private func pingCurrentLocation(using pingService: LocationPingServiceProtocol) async {
        guard let coordinate = state.bindings.mapCenterLocation else {
            MXLog.warning("[LocationPingService] No coordinate available yet, skipping ping")
            return
        }
        let accuracy = state.bindings.geolocationUncertainty ?? 0.0
        let geoURI = GeoURI(latitude: coordinate.latitude,
                            longitude: coordinate.longitude,
                            uncertainty: accuracy)
        
        switch await pingService.sendPing(latitude: geoURI.latitude,
                                          longitude: geoURI.longitude,
                                          accuracy: accuracy,
                                          sourceTimestamp: Date()) {
        case .success:
            MXLog.info("[LocationPingService] Live ping sent — lat: \(geoURI.latitude), lon: \(geoURI.longitude)")
        case .failure(let error):
            MXLog.error("[LocationPingService] Live ping failed: \(error)")
        }
    }
}