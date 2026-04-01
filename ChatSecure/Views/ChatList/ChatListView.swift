// Views/ChatList/ChatListView.swift
// SecureChat — WhatsApp-style chat list screen

import SwiftUI

struct ChatListView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showingAddContact = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // Header
                ChatListHeader(viewModel: viewModel, showingAddContact: $showingAddContact)

                // Search
                if viewModel.isSearching {
                    SearchBarView(text: $viewModel.searchText)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Tabs
                ChatTabBar(selected: $viewModel.selectedTab)

                // Encryption banner
                EncryptionBanner(compact: false)

                // Chat list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.filteredConversations.enumerated()),
                                id: \.element.id) { index, conversation in
                            let contact = viewModel.contacts[conversation.id]

                            ChatListRow(
                                conversation: conversation,
                                contact: contact,
                                isTyping: viewModel.isTyping(conversation.id)
                            )
                            .onTapGesture {
                                viewModel.selectConversation(conversation.id)
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                    }
                }
                .background(ChatColors.bg)
            }
            .background(ChatColors.bg)

            // FAB
            FloatingActionButton()
        }
        .sheet(isPresented: $showingAddContact) {
            AddContactView(viewModel: viewModel)
        }
    }
}

// MARK: — Header

private struct ChatListHeader: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var showingAddContact: Bool

    var body: some View {
        HStack {
            Text("SecureChat")
                .font(ChatFonts.title)
                .foregroundStyle(ChatColors.textPrimary)

            Spacer()

            HStack(spacing: 18) {
                Button { } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 18))
                        .foregroundStyle(ChatColors.textSecondary)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.isSearching.toggle()
                        if !viewModel.isSearching { viewModel.searchText = "" }
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18))
                        .foregroundStyle(ChatColors.textSecondary)
                }

                Menu {
                    Button {
                        showingAddContact = true
                    } label: {
                        Text("Add Contact")
                    }
                    
                    Button {
                        print("Settings tapped")
                    } label: {
                        Text("Settings")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18))
                        .foregroundStyle(ChatColors.textSecondary)
                        .rotationEffect(.degrees(90))
                    // Adding a slight frame ensures a good tap target area
                        .frame(width: 24, height: 24)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(ChatColors.panelHeader)
    }
}

// MARK: — Search Bar

private struct SearchBarView: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(ChatColors.textMuted)

            TextField("Search or start new chat", text: $text)
                .font(.system(size: 14))
                .foregroundStyle(ChatColors.textPrimary)
                .tint(ChatColors.teal)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(ChatColors.textMuted)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(ChatColors.inputBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ChatColors.panelHeader)
    }
}

// MARK: — Chat List Row

struct ChatListRow: View {
    let conversation: Conversation
    let contact: Contact?
    let isTyping: Bool

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 13) {
            // Avatar
            AvatarView(
                emoji: contact?.emoji ?? "👤",
                size: ChatDimensions.avatarLarge,
                showOnline: true,
                isOnline: contact?.isOnline ?? false
            )

            // Content
            VStack(alignment: .leading, spacing: 2) {
                // Top row: name + time
                HStack {
                    Text(contact?.name ?? "Unknown")
                        .font(ChatFonts.chatName)
                        .foregroundStyle(ChatColors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(conversation.lastMessageTime)
                        .font(ChatFonts.tiny)
                        .foregroundStyle(
                            conversation.unreadCount > 0
                            ? ChatColors.teal
                            : ChatColors.textMuted
                        )
                }

                // Bottom row: preview + badge
                HStack {
                    if isTyping {
                        Text("typing...")
                            .font(ChatFonts.chatPreview)
                            .foregroundStyle(ChatColors.teal)
                            .italic()
                    } else {
                        // Show tick for own messages
                        if let last = conversation.lastMessage, last.isFromMe {
                            MessageTickView(status: last.status)
                                .scaleEffect(0.85)
                        }

                        Text(conversation.lastMessagePreview)
                            .font(ChatFonts.chatPreview)
                            .foregroundStyle(ChatColors.textMuted)
                            .lineLimit(1)
                    }

                    Spacer()

                    if conversation.isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(ChatColors.textMuted)
                    }

                    UnreadBadge(count: conversation.unreadCount)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isPressed ? Color.white.opacity(0.03) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ChatColors.border)
                .frame(height: 0.5)
                .padding(.leading, 79) // align with content, past avatar
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: — Floating Action Button

private struct FloatingActionButton: View {
    @State private var isHovered = false

    var body: some View {
        Button { } label: {
            Image(systemName: "message.fill")
                .font(.system(size: 22))
                .foregroundStyle(ChatColors.bgDeep)
                .frame(width: ChatDimensions.fabSize,
                       height: ChatDimensions.fabSize)
                .background(ChatColors.teal)
                .clipShape(RoundedRectangle(cornerRadius: ChatDimensions.fabRadius))
                .shadow(color: ChatColors.teal.opacity(0.35), radius: 10, y: 4)
                .scaleEffect(isHovered ? 1.08 : 1)
        }
        .padding(20)
        .onHover { isHovered = $0 }
    }
}
