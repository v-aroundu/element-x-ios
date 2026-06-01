//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

final class UserDiscoveryService: UserDiscoveryServiceProtocol {
    private let clientProxy: ClientProxyProtocol
    
    init(clientProxy: ClientProxyProtocol) {
        self.clientProxy = clientProxy
    }

    func searchProfiles(with searchQuery: String) async -> Result<[UserProfileProxy], UserDiscoveryErrorType> {
        // If the user typed just a username (no @ prefix and no colon), auto-build a
        // full Matrix ID using the logged-in user's homeserver, e.g. "alice" → "@alice:messenger.aroundu.app".
        let resolvedQuery = resolveQuery(searchQuery)
        
        async let queriedProfile = profileIfPossible(with: resolvedQuery)

        do {
            async let searchedUsers = clientProxy.searchUsers(searchTerm: resolvedQuery, limit: 10).get()
            let users = try await merge(queriedProfile: queriedProfile, searchResults: searchedUsers)
            return .success(filterAccountOwner(users))
        } catch {
            // we want to show the profile (if any) even if the search fails
            if let queriedProfile = await queriedProfile {
                return .success([queriedProfile])
            } else {
                return .failure(.failedSearchingUsers)
            }
        }
    }
    
    /// Turns a bare username like "alice" into "@alice:homeserver.domain".
    /// Leaves already-complete Matrix IDs and other strings unchanged.
    private func resolveQuery(_ query: String) -> String {
        // Already a full Matrix ID or contains special characters — leave as-is.
        guard !query.hasPrefix("@"), !query.contains(":"), !query.isEmpty else {
            return query
        }
        // Extract the homeserver domain from the logged-in user's ID.
        let userID = clientProxy.userID
        guard let colonIndex = userID.firstIndex(of: ":") else { return query }
        let homeserver = String(userID[userID.index(after: colonIndex)...])
        return "@\(query):\(homeserver)"
    }

    private func merge(queriedProfile: UserProfileProxy?, searchResults: SearchUsersResultsProxy) -> [UserProfileProxy] {
        let searchResults = searchResults.results
        
        guard let queriedProfile else {
            return searchResults
        }

        let filteredSearchResult = searchResults.filter {
            $0.userID != queriedProfile.userID
        }

        return [queriedProfile] + filteredSearchResult
    }
    
    private func profileIfPossible(with searchQuery: String) async -> UserProfileProxy? {
        guard searchQuery.isMatrixIdentifier, searchQuery != clientProxy.userID else {
            return nil
        }
        
        // Only return a profile when it actually exists on the server.
        // Returning a stub profile for an unknown ID causes the "can't be found" warning to appear.
        return try? await clientProxy.profile(for: searchQuery).get()
    }

    private func filterAccountOwner(_ profiles: [UserProfileProxy]) -> [UserProfileProxy] {
        let accountOwnerID = clientProxy.userID
        return profiles.filter { $0.userID != accountOwnerID }
    }
}

private extension String {
    var isMatrixIdentifier: Bool {
        MatrixEntityRegex.isMatrixUserIdentifier(self)
    }
}
