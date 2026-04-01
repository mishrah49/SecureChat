// Theme/ChatTheme.swift
// SecureChat — WhatsApp dark theme design tokens

import SwiftUI

// MARK: — Colors

enum ChatColors {
    // Backgrounds
    static let bg              = Color(hex: 0x111B21)
    static let bgDeep          = Color(hex: 0x0B141A)
    static let panel           = Color(hex: 0x1F2C34)
    static let panelHeader     = Color(hex: 0x202C33)
    static let chatBg          = Color(hex: 0x0B141A)
    static let inputBg         = Color(hex: 0x2A3942)
    static let searchBg        = Color(hex: 0x202C33)

    // Bubbles
    static let outgoing        = Color(hex: 0x005C4B)
    static let incoming        = Color(hex: 0x202C33)

    // Teal family
    static let teal            = Color(hex: 0x00A884)
    static let tealDark        = Color(hex: 0x008069)
    static let tealLight       = Color(hex: 0x53BDEB)

    // Text
    static let textPrimary     = Color(hex: 0xE9EDEF)
    static let textSecondary   = Color(hex: 0x8696A0)
    static let textMuted       = Color(hex: 0x667781)

    // Misc
    static let border          = Color.white.opacity(0.08)
    static let unreadBadge     = Color(hex: 0x00A884)
    static let danger          = Color(hex: 0xEA4335)

    // Gradients
    static let avatarGradient  = LinearGradient(
        colors: [tealDark, teal],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: — Hex Color Extension

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: — Typography

enum ChatFonts {
    static let title      = Font.system(size: 21, weight: .bold)
    static let header     = Font.system(size: 15.5, weight: .semibold)
    static let body       = Font.system(size: 14.2)
    static let caption    = Font.system(size: 12)
    static let tiny       = Font.system(size: 11)
    static let tinyBold   = Font.system(size: 11, weight: .semibold)
    static let badge      = Font.system(size: 11, weight: .bold)
    static let tabLabel   = Font.system(size: 13, weight: .semibold)
    static let chatName   = Font.system(size: 16, weight: .medium)
    static let chatPreview = Font.system(size: 13.5)
    static let timestamp  = Font.system(size: 10.5)
    static let msgSender  = Font.system(size: 12, weight: .semibold)
}

// MARK: — Dimensions

enum ChatDimensions {
    static let avatarLarge:  CGFloat = 50
    static let avatarMedium: CGFloat = 38
    static let avatarSmall:  CGFloat = 32
    static let onlineDot:    CGFloat = 12
    static let badgeMin:     CGFloat = 20
    static let bubbleRadius: CGFloat = 9
    static let bubbleTail:   CGFloat = 2
    static let inputRadius:  CGFloat = 22
    static let fabSize:      CGFloat = 54
    static let fabRadius:    CGFloat = 16
    static let sendButton:   CGFloat = 44
    static let maxBubbleWidth: CGFloat = 0.78  // percentage of screen
}
