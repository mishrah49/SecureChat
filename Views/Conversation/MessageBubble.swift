// Views/Conversation/MessageBubble.swift
// SecureChat — WhatsApp-style message bubble

import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    let contact: Contact?
    let showSenderName: Bool

    init(message: ChatMessage, contact: Contact? = nil, showSenderName: Bool = false) {
        self.message = message
        self.contact = contact
        self.showSenderName = showSenderName
    }

    private var isMe: Bool { message.isFromMe }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isMe { Spacer(minLength: 60) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 0) {
                // Sender name (for groups)
                if showSenderName && !isMe {
                    Text(contact?.name ?? "Unknown")
                        .font(ChatFonts.msgSender)
                        .foregroundStyle(senderColor)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 1)
                }

                // Bubble content
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(message.text)
                        .font(ChatFonts.body)
                        .foregroundStyle(ChatColors.textPrimary)
                        .lineSpacing(2)

                    // Metadata: time + tick
                    HStack(spacing: 3) {
                        Text(message.formattedTime)
                            .font(ChatFonts.timestamp)
                            .foregroundStyle(.white.opacity(0.45))

                        if isMe {
                            MessageTickView(status: message.status)
                        }
                    }
                    .offset(y: 4) // Align to bottom of text
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(bubbleBackground)
            }

            if !isMe { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
    }

    // MARK: — Bubble Shape

    private var bubbleBackground: some View {
        BubbleShape(isFromMe: isMe)
            .fill(isMe ? ChatColors.outgoing : ChatColors.incoming)
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
    }

    // MARK: — Sender color (cycle for groups)

    private var senderColor: Color {
        let colors: [Color] = [
            ChatColors.teal,
            Color(hex: 0xFF6B6B),
            Color(hex: 0xFFA726),
            Color(hex: 0xAB47BC),
            Color(hex: 0x42A5F5),
        ]
        let hash = abs(message.senderId.hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: — Custom Bubble Shape with tail

struct BubbleShape: Shape {
    let isFromMe: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = ChatDimensions.bubbleRadius
        let tail: CGFloat = ChatDimensions.bubbleTail

        var path = Path()

        if isFromMe {
            // Outgoing: sharp bottom-right corner
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(-90), endAngle: .degrees(0),
                        clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tail))
            // Sharp tail
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                        radius: r, startAngle: .degrees(90), endAngle: .degrees(180),
                        clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(180), endAngle: .degrees(270),
                        clockwise: false)
        } else {
            // Incoming: sharp bottom-left corner
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(-90), endAngle: .degrees(0),
                        clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                        radius: r, startAngle: .degrees(0), endAngle: .degrees(90),
                        clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            // Sharp tail
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(180), endAngle: .degrees(270),
                        clockwise: false)
        }

        path.closeSubpath()
        return path
    }
}
