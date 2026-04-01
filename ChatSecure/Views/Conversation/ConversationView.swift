// Views/Conversation/ConversationView.swift
// SecureChat — WhatsApp-style conversation screen

import SwiftUI

struct ConversationView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var messageText: String = ""
    @FocusState private var isInputFocused: Bool

    private var conversation: Conversation? { viewModel.selectedConversation }
    private var contact: Contact? { viewModel.selectedContact }

    var body: some View {
        if let conversation, let contact {
            VStack(spacing: 0) {
                // Header
                ConversationHeader(
                    contact: contact,
                    isTyping: viewModel.isTyping(conversation.id),
                    onBack: { viewModel.goBack() }
                )

                // Messages area
                ZStack {
                    // Background
                    ChatColors.chatBg.ignoresSafeArea()
                    WallpaperOverlay()

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                // Date chip
                                DateChip(text: "TODAY")
                                    .padding(.top, 8)
                                    .padding(.bottom, 6)

                                // Encryption notice
                                HStack {
                                    Spacer()
                                    EncryptionBanner(compact: true)
                                    Spacer()
                                }
                                .padding(.bottom, 10)

                                // Messages
                                ForEach(conversation.messages) { message in
                                    MessageBubble(
                                        message: message,
                                        contact: viewModel.contacts[message.senderId],
                                        showSenderName: contact.isGroup && !message.isFromMe
                                    )
                                    .id(message.id)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.95)
                                            .combined(with: .opacity)
                                            .combined(with: .move(edge: .bottom)),
                                        removal: .opacity
                                    ))
                                }

                                // Typing indicator
                                if viewModel.isTyping(conversation.id) {
                                    TypingBubble()
                                        .id("typing")
                                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: conversation.messages.count) { _, _ in
                            withAnimation(.easeOut(duration: 0.2)) {
                                if let last = conversation.messages.last {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: viewModel.typingUsers) { _, _ in
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("typing", anchor: .bottom)
                            }
                        }
                        .onAppear {
                            if let last = conversation.messages.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Input bar
                MessageInputBar(
                    text: $messageText,
                    isFocused: $isInputFocused,
                    onSend: {
                        viewModel.sendMessage(messageText)
                        messageText = ""
                    }
                )
            }
            .background(ChatColors.bg)
        }
    }
}

// MARK: — Conversation Header

struct ConversationHeader: View {
    let contact: Contact
    let isTyping: Bool
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Back button
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(ChatColors.textSecondary)
            }
            .padding(.trailing, -2)

            // Avatar
            AvatarView(
                emoji: contact.emoji,
                size: ChatDimensions.avatarMedium
            )

            // Name + status
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.name)
                    .font(ChatFonts.header)
                    .foregroundStyle(ChatColors.textPrimary)
                    .lineLimit(1)

                if isTyping {
                    Text("typing...")
                        .font(ChatFonts.caption)
                        .foregroundStyle(ChatColors.teal)
                        .transition(.opacity)
                } else {
                    Text(contact.statusText)
                        .font(ChatFonts.caption)
                        .foregroundStyle(
                            contact.isOnline
                            ? ChatColors.teal
                            : ChatColors.textMuted
                        )
                        .lineLimit(1)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isTyping)

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                Button { } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(ChatColors.textSecondary)
                }
                Button { } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(ChatColors.textSecondary)
                }
                Button { } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17))
                        .foregroundStyle(ChatColors.textSecondary)
                        .rotationEffect(.degrees(90))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(ChatColors.panelHeader)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ChatColors.border)
                .frame(height: 0.5)
        }
    }
}

// MARK: — Typing Bubble

private struct TypingBubble: View {
    var body: some View {
        HStack {
            HStack(spacing: 0) {
                TypingIndicator()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                BubbleShape(isFromMe: false)
                    .fill(ChatColors.incoming)
                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
            )

            Spacer()
        }
        .padding(.horizontal, 6)
    }
}

// MARK: — Message Input Bar

struct MessageInputBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            // Emoji button
            Button { } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 22))
                    .foregroundStyle(ChatColors.textMuted)
            }

            // Attachment
            Button { } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 20))
                    .foregroundStyle(ChatColors.textMuted)
                    .rotationEffect(.degrees(45))
            }

            // Text field
            HStack {
                TextField("Message", text: $text, axis: .vertical)
                    .font(.system(size: 14.5))
                    .foregroundStyle(ChatColors.textPrimary)
                    .tint(ChatColors.teal)
                    .focused(isFocused)
                    .lineLimit(1...6)
                    .onSubmit { if hasText { onSend() } }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(ChatColors.inputBg)
            .clipShape(RoundedRectangle(cornerRadius: ChatDimensions.inputRadius))

            // Send / Mic button
            Button {
                if hasText { onSend() }
            } label: {
                Image(systemName: hasText ? "paperplane.fill" : "mic.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(ChatColors.bgDeep)
                    .frame(width: ChatDimensions.sendButton,
                           height: ChatDimensions.sendButton)
                    .background(ChatColors.teal)
                    .clipShape(Circle())
            }
            .animation(.easeInOut(duration: 0.15), value: hasText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(ChatColors.panelHeader)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ChatColors.border)
                .frame(height: 0.5)
        }
    }
}
