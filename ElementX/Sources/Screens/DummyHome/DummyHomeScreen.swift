//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// A convincing-looking fake home screen shown when the duress (dummy) PIN is entered.
/// It shows placeholder rooms and no real data.
struct DummyHomeScreen: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(DummyRoom.placeholders) { room in
                    DummyRoomRow(room: room)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
    }
}

// MARK: - Supporting types

private struct DummyRoom: Identifiable {
    let id: String
    let name: String
    let lastMessage: String
    let time: String
    let unreadCount: Int
    
    static let placeholders: [DummyRoom] = [
        .init(id: "1", name: "Alex", lastMessage: "Sounds good, see you then!", time: "9:41 AM", unreadCount: 2),
        .init(id: "2", name: "Work Group", lastMessage: "Meeting at 3pm confirmed", time: "Yesterday", unreadCount: 0),
        .init(id: "3", name: "Mom", lastMessage: "Don't forget dinner on Sunday", time: "Yesterday", unreadCount: 1),
        .init(id: "4", name: "Jordan", lastMessage: "Haha that's hilarious", time: "Tuesday", unreadCount: 0),
        .init(id: "5", name: "Sarah", lastMessage: "Thanks for the help!", time: "Monday", unreadCount: 0),
        .init(id: "6", name: "Book Club", lastMessage: "I loved chapter 7", time: "Mon", unreadCount: 0),
        .init(id: "7", name: "David", lastMessage: "Let me know when you're free", time: "Sun", unreadCount: 0),
    ]
}

private struct DummyRoomRow: View {
    let room: DummyRoom
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.compound.bgSubtlePrimary)
                .frame(width: 48, height: 48)
                .overlay(
                    Text(String(room.name.prefix(1)))
                        .font(.compound.bodyLGSemibold)
                        .foregroundColor(.compound.textSecondary)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(room.name)
                        .font(.compound.bodyLGSemibold)
                        .foregroundColor(.compound.textPrimary)
                    Spacer()
                    Text(room.time)
                        .font(.compound.bodySM)
                        .foregroundColor(.compound.textSecondary)
                }
                
                HStack {
                    Text(room.lastMessage)
                        .font(.compound.bodyMD)
                        .foregroundColor(.compound.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    if room.unreadCount > 0 {
                        Text("\(room.unreadCount)")
                            .font(.compound.bodySMSemibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.compound.iconAccentTertiary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Previews

struct DummyHomeScreen_Previews: PreviewProvider {
    static var previews: some View {
        DummyHomeScreen()
    }
}
