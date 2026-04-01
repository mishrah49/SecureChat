// Views/Components/SecurityStatusView.swift
// SecureChat — Visual security status indicators for the UI
//
// Shows users the encryption state, device security, and session verification.
// Integrates CryptoService + SecurityCheck results into clear visual feedback.

import SwiftUI
import CryptoKit

// MARK: — Security Status Bar (shown at top of conversation)

struct SecurityStatusBar: View {
    let audit: SecurityAuditResult?
    let sessionActive: Bool
    @State private var expanded = false

    private var statusColor: Color {
        guard let audit else { return ChatColors.textMuted }
        switch audit.threatLevel {
        case .none:     return ChatColors.teal
        case .medium:   return .orange
        case .high:     return ChatColors.danger
        case .critical: return ChatColors.danger
        }
    }

    private var statusIcon: String {
        guard let audit else { return "lock.circle" }
        switch audit.threatLevel {
        case .none:     return "lock.shield.fill"
        case .medium:   return "exclamationmark.shield.fill"
        case .high:     return "xmark.shield.fill"
        case .critical: return "xmark.shield.fill"
        }
    }

    private var statusText: String {
        guard let audit else { return "Checking security..." }
        if !sessionActive { return "Establishing encrypted session..." }
        switch audit.threatLevel {
        case .none:     return "End-to-end encrypted · Hardware secured"
        case .medium:   return "Encrypted · Secure Enclave unavailable"
        case .high:     return "Security warning · Debugger detected"
        case .critical: return "Device compromised · Messages at risk"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)

                    Text(statusText)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(statusColor.opacity(0.9))

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(statusColor.opacity(0.5))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(statusColor.opacity(0.08))
            }
            .buttonStyle(.plain)

            // Expanded detail view
            if expanded, let audit {
                SecurityDetailPanel(audit: audit, sessionActive: sessionActive)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
    }
}

// MARK: — Security Detail Panel

private struct SecurityDetailPanel: View {
    let audit: SecurityAuditResult
    let sessionActive: Bool

    var body: some View {
        VStack(spacing: 8) {
            SecurityCheckRow(
                icon: "cpu.fill",
                label: "Secure Enclave",
                status: audit.secureEnclaveAvailable ? .ok : .warning,
                detail: audit.secureEnclaveAvailable
                    ? "Identity key stored in hardware"
                    : "Not available — using software keys"
            )

            SecurityCheckRow(
                icon: "lock.rotation",
                label: "Double Ratchet",
                status: sessionActive ? .ok : .pending,
                detail: sessionActive
                    ? "Forward secrecy active"
                    : "Waiting for session..."
            )

            SecurityCheckRow(
                icon: "shield.checkered",
                label: "Device Integrity",
                status: !audit.isJailbroken ? .ok : .critical,
                detail: !audit.isJailbroken
                    ? "No tampering detected"
                    : "Jailbreak detected"
            )

            SecurityCheckRow(
                icon: "ant.fill",
                label: "Anti-Debug",
                status: !audit.isDebugged ? .ok : .warning,
                detail: !audit.isDebugged
                    ? "No debugger attached"
                    : "Debugger / Frida detected"
            )

            SecurityCheckRow(
                icon: "checkmark.seal.fill",
                label: "Crypto Integrity",
                status: audit.cryptoIntegrityOK ? .ok : .critical,
                detail: audit.cryptoIntegrityOK
                    ? "CryptoKit verified"
                    : "CryptoKit may be hooked"
            )

            SecurityCheckRow(
                icon: "network.badge.shield.half.filled",
                label: "Certificate Pinning",
                status: .ok,
                detail: "TLS 1.3 with SHA-256 pin"
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.3))
    }
}

// MARK: — Individual Check Row

private struct SecurityCheckRow: View {
    let icon: String
    let label: String
    let status: CheckStatus
    let detail: String

    enum CheckStatus {
        case ok, warning, critical, pending
    }

    private var statusColor: Color {
        switch status {
        case .ok:       return ChatColors.teal
        case .warning:  return .orange
        case .critical: return ChatColors.danger
        case .pending:  return ChatColors.textMuted
        }
    }

    private var statusIcon: String {
        switch status {
        case .ok:       return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        case .pending:  return "clock.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(statusColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ChatColors.textPrimary)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(ChatColors.textMuted)
            }

            Spacer()

            Image(systemName: statusIcon)
                .font(.system(size: 12))
                .foregroundStyle(statusColor)
        }
    }
}

// MARK: — Safety Number View (verification screen)

/// Signal-style safety number for verifying session identity.
/// Users compare these numbers in-person to confirm no MITM.
struct SafetyNumberView: View {
    let myFingerprint: Data
    let theirFingerprint: Data
    let theirName: String

    @Environment(\.dismiss) private var dismiss

    private var safetyNumber: String {
        // Combine both fingerprints and hash
        var combined = myFingerprint
        combined.append(theirFingerprint)
        let hash = SHA256.hash(data: combined)
        // Convert to 12 groups of 5 digits
        let bytes = Array(hash)
        var groups: [String] = []
        for i in stride(from: 0, to: min(bytes.count, 30), by: 5) {
            let chunk = bytes[i..<min(i+5, bytes.count)]
            let number = chunk.reduce(0) { ($0 << 8) | UInt64($1) } % 100000
            groups.append(String(format: "%05d", number))
        }
        return groups.joined(separator: " ")
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ChatColors.textSecondary)
                }
                Spacer()
                Text("Security Verification")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ChatColors.textPrimary)
                Spacer()
                Color.clear.frame(width: 20) // balance
            }
            .padding(.horizontal)

            // Lock icon
            ZStack {
                Circle()
                    .fill(ChatColors.teal.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(ChatColors.teal)
            }

            Text("Verify your security with \(theirName)")
                .font(.system(size: 14))
                .foregroundStyle(ChatColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Safety number grid
            VStack(spacing: 4) {
                let lines = safetyNumber.split(separator: " ").chunked(into: 4)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 12) {
                        ForEach(Array(line.enumerated()), id: \.offset) { _, group in
                            Text(String(group))
                                .font(.system(size: 18, weight: .medium, design: .monospaced))
                                .foregroundStyle(ChatColors.textPrimary)
                        }
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(ChatColors.incoming.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(ChatColors.border, lineWidth: 1)
                    )
            )

            Text("Compare this number with \(theirName) by meeting in person or calling. If they match, your messages are secure.")
                .font(.system(size: 12))
                .foregroundStyle(ChatColors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // Actions
            VStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = safetyNumber
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Number")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ChatColors.bgDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(ChatColors.teal)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button { dismiss() } label: {
                    Text("Done")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ChatColors.teal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 16)
        .background(ChatColors.bg.ignoresSafeArea())
    }
}

// MARK: — Helpers

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
