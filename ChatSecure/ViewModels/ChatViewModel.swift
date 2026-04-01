// ViewModels/ChatViewModel.swift
// SecureChat — Main state management

import SwiftUI
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    
    // MARK: — Published State
    
    @Published var conversations: [Conversation]
    @Published var selectedConversationId: String?
    @Published var typingUsers: Set<String> = []
    @Published var searchText: String = ""
    @Published var isSearching: Bool = false
    @Published var selectedTab: ChatTab = .chats
    
    @Published var contacts: [String: Contact]
    
    // MARK: — Init
    
    init() {
        self.contacts = SampleData.contacts
        self.conversations = SampleData.makeConversations()
    }
    
    // MARK: — Computed
    
    var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationId }
    }
    
    var selectedContact: Contact? {
        guard let id = selectedConversationId else { return nil }
        return contacts[id]
    }
    
    var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return conversations }
        return conversations.filter { conv in
            let name = contacts[conv.id]?.name.lowercased() ?? ""
            let preview = conv.lastMessagePreview.lowercased()
            let query = searchText.lowercased()
            return name.contains(query) || preview.contains(query)
        }
    }
    
    // MARK: — Actions
    
    func selectConversation(_ id: String) {
        selectedConversationId = id
        // Clear unread
        if let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx].unreadCount = 0
        }
    }
    
    func goBack() {
        selectedConversationId = nil
    }
    
    func sendMessage(_ text: String) {
        guard let convId = selectedConversationId,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let idx = conversations.firstIndex(where: { $0.id == convId })
        else { return }
        
        let msg = ChatMessage(
            id: UUID().uuidString,
            conversationId: convId,
            senderId: "me",
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: Date(),
            status: .sending
        )
        
        conversations[idx].messages.append(msg)
        
        // Animate: sending → sent → delivered → read
        animateTickProgression(messageId: msg.id, conversationId: convId)
        
        // Simulate reply
        simulateReply(for: convId)
    }
    
    func addHiddenContact(name: String) {
        let newId = UUID().uuidString
        
        // Note: Adjust these initializers if your Contact or Conversation structs differ slightly
        let newContact = Contact(
            id: newId,          // Assuming your Contact has an ID (if not, you can omit)
            name: name,
            emoji: "👋",
            isOnline: true
        )
        
        let myMessage = ChatMessage(
            id: UUID().uuidString,
            conversationId: newId,
            senderId: "me",
            text: "Hi",
            timestamp: Date().addingTimeInterval(-10),
            status: .read
        )
        
        let theirMessage = ChatMessage(
            id: UUID().uuidString,
            conversationId: newId,
            senderId: newId, // The senderId is the contact's ID
            text: "Hi",
            timestamp: Date(),
            status: .read
        )
        
        let newConversation = Conversation(
            id: newId,
            messages: [myMessage, theirMessage],
            unreadCount: 1, isPinned: false,
            isMuted: false
        )
        
        // Update state
        contacts[newId] = newContact
        
        withAnimation {
            conversations.insert(newConversation, at: 0) // Put at the top of the chat list
        }
    }
    
    // MARK: — Tick Progression
    
    private func animateTickProgression(messageId: String, conversationId: String) {
        // sending → sent (0.3s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateMessageStatus(messageId: messageId, convId: conversationId, status: .sent)
        }
        // sent → delivered (0.8s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.updateMessageStatus(messageId: messageId, convId: conversationId, status: .delivered)
        }
        // delivered → read (2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.updateMessageStatus(messageId: messageId, convId: conversationId, status: .read)
        }
    }
    
    private func updateMessageStatus(messageId: String, convId: String, status: MessageStatus) {
        guard let convIdx = conversations.firstIndex(where: { $0.id == convId }),
              let msgIdx = conversations[convIdx].messages.firstIndex(where: { $0.id == messageId })
        else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            conversations[convIdx].messages[msgIdx].status = status
        }
    }
    
    // MARK: — Typing + Auto-Reply
    
    private func simulateReply(for convId: String) {
        // Show typing
        withAnimation { typingUsers.insert(convId) }
        
        let delay = Double.random(in: 1.5...3.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            withAnimation { self.typingUsers.remove(convId) }
            
            let replies = ["Nice work! 🔥",
                "That makes sense 👍", "Interesting approach!",
                "Let me think about it", "Yeah I agree",
                "Can you explain more?",
                "Let's discuss tomorrow", "Sounds good to me",
                "Will look into it", "Great point 💡",
            ]
            
            let reply = ChatMessage(
                id: UUID().uuidString,
                conversationId: convId,
                senderId: convId,
                text: replies.first!,
                timestamp: Date(),
                status: .read
            )
            
            if let idx = self.conversations.firstIndex(where: { $0.id == convId }) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self.conversations[idx].messages.append(reply)
                }
            }
        }
    }
    
    func isTyping(_ contactId: String) -> Bool {
        typingUsers.contains(contactId)
    }
}

// MARK: — Tab

enum ChatTab: String, CaseIterable {
    case chats  = "Chats"
    case status = "Status"
    case calls  = "Calls"
}
