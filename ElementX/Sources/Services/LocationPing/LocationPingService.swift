
//
// LocationPingService.swift
// ElementX
//
// Sends live location pings to the AroundU backend API.
//

import CoreLocation
import Foundation

// MARK: - Protocol

protocol LocationPingServiceProtocol {
    func sendPing(latitude: Double,
                  longitude: Double,
                  accuracy: Double,
                  sourceTimestamp: Date) async -> Result<Void, LocationPingServiceError>
}

// MARK: - Errors

enum LocationPingServiceError: Error {
    case noAccessToken
    case networkError(Error)
    case serverError(Int)
    case encodingError(Error)
}

// MARK: - Service

final class LocationPingService: LocationPingServiceProtocol {
    private let baseURL = URL(string: "https://api.m.aroundu.app/api")!
    private let session: URLSession
    private let clientProxy: ClientProxyProtocol

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(clientProxy: ClientProxyProtocol, session: URLSession = .shared) {
        self.clientProxy = clientProxy
        self.session = session
    }

    // MARK: - LocationPingServiceProtocol

    func sendPing(latitude: Double,
                  longitude: Double,
                  accuracy: Double,
                  sourceTimestamp: Date) async -> Result<Void, LocationPingServiceError> {
        guard let accessToken = clientProxy.accessToken else {
            MXLog.error("[LocationPingService] No access token available")
            return .failure(.noAccessToken)
        }

        let endpoint = baseURL.appendingPathComponent("/app/location-pings")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude,
            "accuracy": accuracy,
            "sourceTimestamp": isoFormatter.string(from: sourceTimestamp)
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            MXLog.error("[LocationPingService] Failed encoding body: \(error)")
            return .failure(.encodingError(error))
        }

        do {
            let (_, response) = try await session.dataWithRetry(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                guard (200..<300).contains(httpResponse.statusCode) else {
                    MXLog.error("[LocationPingService] Server returned \(httpResponse.statusCode)")
                    return .failure(.serverError(httpResponse.statusCode))
                }
            }
            MXLog.info("[LocationPingService] Ping sent — lat: \(latitude), lon: \(longitude)")
            return .success(())
        } catch {
            MXLog.error("[LocationPingService] Network error: \(error)")
            return .failure(.networkError(error))
        }
    }
}
