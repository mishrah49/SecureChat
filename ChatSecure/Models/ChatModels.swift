// Models/ChatModels.swift
// SecureChat — WhatsApp-style encrypted messaging UI

import SwiftUI
import Foundation

// MARK: — Message Status

enum MessageStatus: String, Codable, CaseIterable {
    case sending
    case sent
    case delivered
    case read
    case failed
}

// MARK: — Message

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let conversationId: String
    let senderId: String
    let text: String
    let timestamp: Date
    var status: MessageStatus

    var isFromMe: Bool { senderId == "me" }

    var formattedTime: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: timestamp).lowercased()
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status
    }
}

// MARK: — Contact

struct Contact: Identifiable {
    let id: String
    let name: String
    let emoji: String
    let about: String
    var isOnline: Bool
    var lastSeen: String?
    var isGroup: Bool

    init(id: String, name: String, emoji: String, about: String = "",
         isOnline: Bool = false, lastSeen: String? = nil, isGroup: Bool = false) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.about = about
        self.isOnline = isOnline
        self.lastSeen = lastSeen
        self.isGroup = isGroup
    }

    var statusText: String {
        if isGroup { return about }
        if isOnline { return "online" }
        if let lastSeen { return "last seen \(lastSeen)" }
        return ""
    }
}

// MARK: — Conversation (Chat list item)

struct Conversation: Identifiable {
    let id: String           // matches contact id
    var messages: [ChatMessage]
    var unreadCount: Int
    var isPinned: Bool
    var isMuted: Bool

    var lastMessage: ChatMessage? { messages.last }

    var lastMessagePreview: String {
        guard let msg = lastMessage else { return "" }
        let prefix = msg.isFromMe ? "You: " : ""
        return "\(prefix)\(msg.text)"
    }

    var lastMessageTime: String {
        guard let msg = lastMessage else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(msg.timestamp) {
            return msg.formattedTime
        } else if calendar.isDateInYesterday(msg.timestamp) {
            return "Yesterday"
        } else {
            let fmt = DateFormatter()
            fmt.dateFormat = "dd/MM/yy"
            return fmt.string(from: msg.timestamp)
        }
    }
}

// MARK: — Sample Data

enum SampleData {
    static let contacts: [String: Contact] = [
        "c1": Contact(id: "c1", name: "Aarav", emoji: "🧑‍💻",
                       about: "Building something cool", isOnline: true),
        "c2": Contact(id: "c2", name: "Priya", emoji: "👩‍🎨",
                       about: "Design is intelligence made visible",
                       isOnline: false, lastSeen: "today at 2:14 pm"),
        "c3": Contact(id: "c3", name: "Rohan", emoji: "🎸",
                       about: "Music | Code | Coffee", isOnline: true),
        "c4": Contact(id: "c4", name: "Sneha", emoji: "📚",
                       about: "Reading between the lines",
                       isOnline: false, lastSeen: "yesterday at 11:30 pm"),
        "c5": Contact(id: "c5", name: "Vikram", emoji: "🏋️",
                       about: "Fitness freak",
                       isOnline: false, lastSeen: "today at 9:45 am"),
        "c6": Contact(id: "c6", name: "Office Team", emoji: "🚀",
                       about: "Group · 5 participants",
                       isOnline: true, isGroup: true),
    ]

    static func makeConversations() -> [Conversation] {
        let now = Date()
        let cal = Calendar.current

        return [
            Conversation(
                id: "c1",
                messages: [
                    ChatMessage(id: "m1", conversationId: "c1", senderId: "c1",
                                text: "Hey! How's the SecureChat project going?",
                                timestamp: cal.date(byAdding: .minute, value: -12, to: now)!,
                                status: .read),
                    ChatMessage(id: "m2", conversationId: "c1", senderId: "me",
                                text: "Making good progress. Finished the Secure Enclave key manager yesterday",
                                timestamp: cal.date(byAdding: .minute, value: -10, to: now)!,
                                status: .read),
                    ChatMessage(id: "m3", conversationId: "c1", senderId: "c1",
                                text: "That's sick. Are you using P-256 or Curve25519?",
                                timestamp: cal.date(byAdding: .minute, value: -9, to: now)!,
                                status: .read),
                    ChatMessage(id: "m4", conversationId: "c1", senderId: "me",
                                text: "SE only supports P-256, so identity key lives there. But X3DH uses Curve25519 — I bridge them by signing the Curve25519 key with the SE key",
                                timestamp: cal.date(byAdding: .minute, value: -7, to: now)!,
                                status: .read),
                    ChatMessage(id: "m5", conversationId: "c1", senderId: "c1",
                                text: "Smart approach. Signal does something similar right?",
                                timestamp: cal.date(byAdding: .minute, value: -6, to: now)!,
                                status: .read),
                    ChatMessage(id: "m6", conversationId: "c1", senderId: "me",
                                text: "Yeah exactly. Except they don't have hardware-backed keys on most Android devices. iOS SE is a huge advantage",
                                timestamp: cal.date(byAdding: .minute, value: -4, to: now)!,
                                status: .read),
                    ChatMessage(id: "m7", conversationId: "c1", senderId: "c1",
                                text: "Check the new encryption module 🔐",
                                timestamp: now, status: .delivered),
                ],
                unreadCount: 2, isPinned: true, isMuted: false
            ),
            Conversation(
                id: "c6",
                messages: [
                    ChatMessage(id: "g1", conversationId: "c6", senderId: "c5",
                                text: "Sprint planning at 3 today",
                                timestamp: cal.date(byAdding: .minute, value: -27, to: now)!,
                                status: .read),
                ],
                unreadCount: 5, isPinned: false, isMuted: false
            ),
            Conversation(
                id: "c2",
                messages: [
                    ChatMessage(id: "p1", conversationId: "c2", senderId: "c2",
                                text: "Can you send me the latest mockups?",
                                timestamp: cal.date(byAdding: .hour, value: -1, to: now)!,
                                status: .read),
                    ChatMessage(id: "p2", conversationId: "c2", senderId: "me",
                                text: "Sure, sending now. I went with a clean minimal look",
                                timestamp: cal.date(byAdding: .minute, value: -50, to: now)!,
                                status: .read),
                    ChatMessage(id: "p3", conversationId: "c2", senderId: "c2",
                                text: "Love the new chat bubbles design ✨",
                                timestamp: cal.date(byAdding: .minute, value: -30, to: now)!,
                                status: .read),
                ],
                unreadCount: 0, isPinned: false, isMuted: false
            ),
            Conversation(
                id: "c3",
                messages: [
                    ChatMessage(id: "r1", conversationId: "c3", senderId: "c3",
                                text: "Bro when are we meeting up?",
                                timestamp: cal.date(byAdding: .day, value: -1, to: now)!,
                                status: .read),
                    ChatMessage(id: "r2", conversationId: "c3", senderId: "me",
                                text: "Let's jam this weekend 🎵",
                                timestamp: cal.date(byAdding: .day, value: -1, to: now)!,
                                status: .read),
                ],
                unreadCount: 0, isPinned: false, isMuted: false
            ),
            Conversation(
                id: "c4",
                messages: [
                    ChatMessage(id: "s1", conversationId: "c4", senderId: "c4",
                                text: "Have you read Sapiens?",
                                timestamp: cal.date(byAdding: .day, value: -3, to: now)!,
                                status: .delivered),
                ],
                unreadCount: 1, isPinned: false, isMuted: false
            ),
            Conversation(
                id: "c5",
                messages: [
                    ChatMessage(id: "v1", conversationId: "c5", senderId: "c5",
                                text: "Hit a new PR today! 120kg deadlift",
                                timestamp: cal.date(byAdding: .day, value: -3, to: now)!,
                                status: .read),
                    ChatMessage(id: "v2", conversationId: "c5", senderId: "me",
                                text: "💪",
                                timestamp: cal.date(byAdding: .day, value: -3, to: now)!,
                                status: .read),
                ],
                unreadCount: 0, isPinned: false, isMuted: false
            ),
        ]
    }
}
