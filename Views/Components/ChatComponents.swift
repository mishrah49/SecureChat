// Views/Components/ChatComponents.swift
// SecureChat — Reusable UI components

import SwiftUI

// MARK: — Avatar

struct AvatarView: View {
    let emoji: String
    let size: CGFloat
    var showOnline: Bool = false
    var isOnline: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(ChatColors.avatarGradient)
                    .frame(width: size, height: size)
                Text(emoji)
                    .font(.system(size: size * 0.44))
            }

            if showOnline && isOnline {
                Circle()
                    .fill(ChatColors.teal)
                    .frame(width: ChatDimensions.onlineDot,
                           height: ChatDimensions.onlineDot)
                    .overlay(
                        Circle()
                            .stroke(ChatColors.bg, lineWidth: 2)
                    )
                    .offset(x: 1, y: 1)
            }
        }
    }
}

// MARK: — Message Tick (read receipts)

struct MessageTickView: View {
    let status: MessageStatus
    
    var body: some View {
        switch status {
        case .sending:
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundStyle(ChatColors.textMuted)
        case .sent:
            SingleCheck()
                .foregroundStyle(ChatColors.textSecondary)
        case .delivered:
            DoubleCheck()
                .foregroundStyle(ChatColors.textSecondary)
        case .read:
            DoubleCheck()
                .foregroundStyle(ChatColors.tealLight)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(ChatColors.danger)
        }
    }
}

private struct SingleCheck: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .semibold))
    }
}

private struct DoubleCheck: View {
    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .offset(x: 5)
        }
        .frame(width: 18)
    }
}

// MARK: — Typing Indicator (three bouncing dots)

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(ChatColors.teal)
                    .frame(width: 7, height: 7)
                    .offset(y: animating ? -4 : 0)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .padding(.vertical, 4)
        .onAppear { animating = true }
    }
}

// MARK: — Unread Badge

struct UnreadBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(ChatFonts.badge)
                .foregroundStyle(ChatColors.bgDeep)
                .padding(.horizontal, 5)
                .frame(minWidth: ChatDimensions.badgeMin,
                       minHeight: ChatDimensions.badgeMin)
                .background(ChatColors.unreadBadge)
                .clipShape(Capsule())
        }
    }
}

// MARK: — Encryption Banner

struct EncryptionBanner: View {
    let compact: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: compact ? 9 : 11))
                .foregroundStyle(ChatColors.textMuted.opacity(0.6))

            Text(compact
                 ? "Messages are end-to-end encrypted. No one outside of this chat, not even SecureChat, can read or listen to them."
                 : "Your messages are end-to-end encrypted with hardware security")
                .font(ChatFonts.tiny)
                .foregroundStyle(ChatColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, compact ? 14 : 10)
        .padding(.vertical, compact ? 6 : 10)
        .frame(maxWidth: compact ? 300 : .infinity)
        .background(
            RoundedRectangle(cornerRadius: compact ? 8 : 0)
                .fill(compact
                      ? ChatColors.incoming.opacity(0.75)
                      : ChatColors.teal.opacity(0.06))
        )
        .overlay(
            compact ? nil : Rectangle()
                .fill(ChatColors.border)
                .frame(height: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        )
    }
}

// MARK: — Date Chip

struct DateChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(ChatFonts.tiny)
            .foregroundStyle(ChatColors.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(ChatColors.bgDeep.opacity(0.85))
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            )
    }
}

// MARK: — Wallpaper pattern overlay

struct WallpaperOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let spacing: CGFloat = 30
                let crossSize: CGFloat = 6
                for x in stride(from: CGFloat(0), through: size.width, by: spacing) {
                    for y in stride(from: CGFloat(0), through: size.height, by: spacing) {
                        // Small + shape
                        var path = Path()
                        path.move(to: CGPoint(x: x - crossSize/2, y: y))
                        path.addLine(to: CGPoint(x: x + crossSize/2, y: y))
                        path.move(to: CGPoint(x: x, y: y - crossSize/2))
                        path.addLine(to: CGPoint(x: x, y: y + crossSize/2))
                        context.stroke(path,
                                       with: .color(.white.opacity(0.03)),
                                       lineWidth: 1)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: — Tab Bar

struct ChatTabBar: View {
    @Binding var selected: ChatTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ChatTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selected = tab
                    }
                } label: {
                    VStack(spacing: 0) {
                        Text(tab.rawValue.uppercased())
                            .font(ChatFonts.tabLabel)
                            .tracking(1)
                            .foregroundStyle(selected == tab
                                             ? ChatColors.teal
                                             : ChatColors.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)

                        Rectangle()
                            .fill(selected == tab
                                  ? ChatColors.teal
                                  : Color.clear)
                            .frame(height: 2.5)
                    }
                }
            }
        }
        .background(ChatColors.panelHeader)
    }
}
