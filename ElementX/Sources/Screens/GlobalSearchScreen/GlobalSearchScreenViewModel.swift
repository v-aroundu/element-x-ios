//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias GlobalSearchScreenViewModelType = StateStoreViewModel<GlobalSearchScreenViewState, GlobalSearchScreenViewAction>

class GlobalSearchScreenViewModel: GlobalSearchScreenViewModelType, GlobalSearchScreenViewModelProtocol {
    private let roomSummaryProvider: RoomSummaryProviderProtocol
    
    private var actionsSubject: PassthroughSubject<GlobalSearchScreenViewModelAction, Never> = .init()
    var actions: AnyPublisher<GlobalSearchScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(roomSummaryProvider: RoomSummaryProviderProtocol,
         mediaProvider: MediaProviderProtocol) {
        self.roomSummaryProvider = roomSummaryProvider
        
        super.init(initialViewState: GlobalSearchScreenViewState(bindings: .init(searchQuery: "")),
                   mediaProvider: mediaProvider)
        
        roomSummaryProvider.roomListPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summaries in
                self?.updateRooms(with: summaries)
            }
            .store(in: &cancellables)
        
        context.$viewState
            .map(\.bindings.searchQuery)
            .removeDuplicates()
            .sink { [weak self] searchQuery in
                if searchQuery.isEmpty {
                    self?.roomSummaryProvider.setFilter(.all(filters: []))
                } else {
                    // Use the SDK's name search so results span all pages,
                    // then client-side filtering adds last-message matches on top.
                    self?.roomSummaryProvider.setFilter(.search(query: searchQuery))
                }
            }
            .store(in: &cancellables)
        
        updateRooms(with: roomSummaryProvider.roomListPublisher.value)
    }
    
    func stop() {
        // This is a shared provider so we should reset the filtering when we are done with the view
        roomSummaryProvider.setFilter(.all(filters: []))
    }
    
    // MARK: - Public
    
    override func process(viewAction: GlobalSearchScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .dismiss:
            actionsSubject.send(.dismiss)
        case .select(let roomID):
            actionsSubject.send(.select(roomID: roomID))
        case .reachedTop:
            updateVisibleRange(edge: .top)
        case .reachedBottom:
            updateVisibleRange(edge: .bottom)
        }
    }
    
    // MARK: - Private
    
    private func updateRooms(with summaries: [RoomSummary]) {
        let query = context.viewState.bindings.searchQuery.lowercased()
        
        let filteredSummaries = if query.isEmpty {
            summaries
        } else {
            summaries.filter { summary in
                if summary.name.lowercased().contains(query) {
                    return true
                }
                if let lastMessage = summary.lastMessage,
                   String(lastMessage.characters).lowercased().contains(query) {
                    return true
                }
                if let alias = summary.canonicalAlias?.lowercased(), alias.contains(query) {
                    return true
                }
                return false
            }
        }
        
        state.rooms = filteredSummaries.compactMap { summary in
            GlobalSearchRoom(id: summary.id,
                             title: summary.name,
                             description: summary.roomListDescription,
                             avatar: summary.avatar)
        }
    }
    
    /// The actual range values don't matter as long as they contain the lower
    /// or upper bounds. updateVisibleRange is a hybrid API that powers both
    /// sliding sync visible range update and list paginations
    /// For lists other than the home screen one we don't care about visible ranges,
    /// we just need the respective bounds to be there to trigger a next page load or
    /// a reset to just one page
    private func updateVisibleRange(edge: UIRectEdge) {
        switch edge {
        case .top:
            roomSummaryProvider.updateVisibleRange(0..<0)
        case .bottom:
            let roomCount = roomSummaryProvider.roomListPublisher.value.count
            roomSummaryProvider.updateVisibleRange(roomCount..<roomCount)
        default:
            break
        }
    }
}
