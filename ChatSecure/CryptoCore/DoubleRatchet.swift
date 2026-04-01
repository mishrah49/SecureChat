// CryptoCore/DoubleRatchet.swift
// SecureChat — Double Ratchet protocol for ongoing message encryption
//
// Every message is encrypted with a unique key. Compromising one key does NOT
// reveal past or future messages (forward secrecy + post-compromise security).
//
// Two ratchets run simultaneously:
// 1. Symmetric ratchet: KDF chain advances per message (like Signal's chain key)
// 2. DH ratchet: New Curve25519 key exchange on each send/receive turn
//
// Uses actor isolation for thread safety (Swift 6 ready).

import CryptoKit
import Foundation

// MARK: — Encrypted Message Wire Format

public struct EncryptedMessage: Codable, Sendable {
    /// AES-256-GCM ciphertext + 16-byte auth tag appended
    public let ciphertext: Data
    /// 12-byte nonce / IV
    public let nonce: Data
    /// Sender's current DH ratchet public key (for receiver to do DH step)
    public let ratchetPublicKey: Data
    /// Message number in the current sending chain
    public let messageNumber: UInt32
    /// Number of messages in the previous sending chain (for out-of-order handling)
    public let previousChainLength: UInt32
}

// MARK: — Errors

public enum DoubleRatchetError: Error, LocalizedError {
    case noSendingChain
    case noReceivingChain
    case decryptionFailed(Error)
    case maxSkipExceeded
    case invalidRatchetKey

    public var errorDescription: String? {
        switch self {
        case .noSendingChain: return "No active sending chain"
        case .noReceivingChain: return "No active receiving chain"
        case .decryptionFailed(let e): return "Decryption failed: \(e.localizedDescription)"
        case .maxSkipExceeded: return "Too many skipped messages"
        case .invalidRatchetKey: return "Invalid DH ratchet key"
        }
    }
}

// MARK: — Double Ratchet Session

public actor DoubleRatchetSession {

    // MARK: — State

    /// Root key — updated on every DH ratchet step
    private var rootKey: SymmetricKey

    /// Sending chain key — advances per sent message
    private var sendingChainKey: SymmetricKey?

    /// Receiving chain key — advances per received message
    private var receivingChainKey: SymmetricKey?

    /// Our current DH ratchet key pair
    private var sendRatchetKey: Curve25519.KeyAgreement.PrivateKey

    /// Their current DH ratchet public key
    private var recvRatchetPublicKey: Curve25519.KeyAgreement.PublicKey?

    /// Counters
    private var sendMessageNumber: UInt32 = 0
    private var recvMessageNumber: UInt32 = 0
    private var previousSendChainLength: UInt32 = 0

    /// Skipped message keys (for out-of-order delivery)
    /// Key: (ratchetPublicKey.hex, messageNumber) → messageKey
    private var skippedKeys: [String: SymmetricKey] = [:]
    private let maxSkip: UInt32 = 1000

    // MARK: — Init

    /// Initialize after X3DH key agreement.
    ///
    /// - Parameters:
    ///   - sharedSecret: Root key from X3DH
    ///   - remoteRatchetKey: Other party's initial ratchet public key (from their prekey)
    ///   - isInitiator: True if this device initiated the session (Alice)
    public init(
        sharedSecret: SymmetricKey,
        remoteRatchetKey: Curve25519.KeyAgreement.PublicKey? = nil,
        isInitiator: Bool
    ) throws {
        self.sendRatchetKey = Curve25519.KeyAgreement.PrivateKey()

        if isInitiator, let remoteKey = remoteRatchetKey {
            // Alice: immediately do a DH ratchet step
            self.recvRatchetPublicKey = remoteKey

            let dhResult = try sendRatchetKey.sharedSecretFromKeyAgreement(with: remoteKey)
            let (newRoot, sendChain) = Self.kdfRootKey(rootKey: sharedSecret, dhOutput: dhResult)
            self.rootKey = newRoot
            self.sendingChainKey = sendChain
        } else {
            // Bob: wait for first message to trigger DH ratchet
            self.rootKey = sharedSecret
            self.sendingChainKey = Self.kdfDeriveChain(from: sharedSecret, label: "initial-send")
        }
    }

    // MARK: — Encrypt

    /// Encrypt a plaintext message.
    /// Each call advances the sending chain — the key is used exactly once.
    public func encrypt(_ plaintext: Data) throws -> EncryptedMessage {
        guard var chainKey = sendingChainKey else {
            throw DoubleRatchetError.noSendingChain
        }

        // Derive message key from chain key
        let messageKey = Self.kdfMessageKey(chainKey: chainKey)

        // Advance chain key
        chainKey = Self.kdfAdvanceChain(chainKey: chainKey)
        sendingChainKey = chainKey

        // Encrypt with AES-256-GCM
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: messageKey, nonce: nonce)

        // Combine ciphertext + tag (standard format)
        var payload = sealed.ciphertext
        payload.append(sealed.tag)

        let message = EncryptedMessage(
            ciphertext: payload,
            nonce: Data(nonce),
            ratchetPublicKey: sendRatchetKey.publicKey.rawRepresentation,
            messageNumber: sendMessageNumber,
            previousChainLength: previousSendChainLength
        )

        sendMessageNumber += 1
        return message
    }

    // MARK: — Decrypt

    /// Decrypt a received message.
    /// Handles DH ratchet steps and out-of-order messages.
    public func decrypt(_ message: EncryptedMessage) throws -> Data {
        // 1. Check skipped message keys first (out-of-order)
        let ratchetHex = message.ratchetPublicKey.hexString
        let skipKey = "\(ratchetHex):\(message.messageNumber)"
        if let cachedKey = skippedKeys.removeValue(forKey: skipKey) {
            return try decryptWithKey(message, key: cachedKey)
        }

        // 2. Check if we need a DH ratchet step (new ratchet key from sender)
        let theirRatchetKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: message.ratchetPublicKey
        )

        let needsRatchet = recvRatchetPublicKey == nil ||
            theirRatchetKey.rawRepresentation != recvRatchetPublicKey!.rawRepresentation

        if needsRatchet {
            // Skip any remaining messages in the old chain
            try skipMessages(until: message.previousChainLength)

            // Perform DH ratchet step
            try performDHRatchet(theirPublicKey: theirRatchetKey)
        }

        // 3. Skip messages in current chain if needed (message number gap)
        try skipMessages(until: message.messageNumber)

        // 4. Derive message key and decrypt
        guard var chainKey = receivingChainKey else {
            throw DoubleRatchetError.noReceivingChain
        }

        let messageKey = Self.kdfMessageKey(chainKey: chainKey)
        chainKey = Self.kdfAdvanceChain(chainKey: chainKey)
        receivingChainKey = chainKey
        recvMessageNumber += 1

        return try decryptWithKey(message, key: messageKey)
    }

    // MARK: — DH Ratchet Step

    /// Perform a DH ratchet: new shared secrets, new chains.
    /// Called when we receive a message with a new ratchet public key.
    private func performDHRatchet(
        theirPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws {
        recvRatchetPublicKey = theirPublicKey
        previousSendChainLength = sendMessageNumber
        sendMessageNumber = 0
        recvMessageNumber = 0

        // Step 1: Derive receiving chain from current send key + their new key
        let dhRecv = try sendRatchetKey.sharedSecretFromKeyAgreement(with: theirPublicKey)
        let (newRoot1, recvChain) = Self.kdfRootKey(rootKey: rootKey, dhOutput: dhRecv)
        rootKey = newRoot1
        receivingChainKey = recvChain

        // Step 2: Generate new send ratchet key pair
        sendRatchetKey = Curve25519.KeyAgreement.PrivateKey()

        // Step 3: Derive new sending chain from new send key + their key
        let dhSend = try sendRatchetKey.sharedSecretFromKeyAgreement(with: theirPublicKey)
        let (newRoot2, sendChain) = Self.kdfRootKey(rootKey: rootKey, dhOutput: dhSend)
        rootKey = newRoot2
        sendingChainKey = sendChain
    }

    // MARK: — Skip handling (out-of-order messages)

    private func skipMessages(until target: UInt32) throws {
        guard target > recvMessageNumber else { return }
        let toSkip = target - recvMessageNumber

        if toSkip > maxSkip {
            throw DoubleRatchetError.maxSkipExceeded
        }

        guard var chainKey = receivingChainKey else { return }

        for i in recvMessageNumber..<target {
            let msgKey = Self.kdfMessageKey(chainKey: chainKey)
            chainKey = Self.kdfAdvanceChain(chainKey: chainKey)

            let ratchetHex = recvRatchetPublicKey?.rawRepresentation.hexString ?? ""
            skippedKeys["\(ratchetHex):\(i)"] = msgKey
        }

        receivingChainKey = chainKey
        recvMessageNumber = target
    }

    // MARK: — Decryption helper

    private func decryptWithKey(_ message: EncryptedMessage, key: SymmetricKey) throws -> Data {
        do {
            let nonce = try AES.GCM.Nonce(data: message.nonce)
            let ct = message.ciphertext

            // Split ciphertext and tag (last 16 bytes)
            guard ct.count > 16 else {
                throw DoubleRatchetError.decryptionFailed(
                    NSError(domain: "crypto", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Ciphertext too short"])
                )
            }

            let tagStart = ct.index(ct.endIndex, offsetBy: -16)
            let ciphertext = ct[ct.startIndex..<tagStart]
            let tag = ct[tagStart..<ct.endIndex]

            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(sealedBox, using: key)
        } catch let error as DoubleRatchetError {
            throw error
        } catch {
            throw DoubleRatchetError.decryptionFailed(error)
        }
    }

    // MARK: — Serialization (for persisting session state)

    public struct SessionState: Codable, Sendable {
        let rootKey: Data
        let sendingChainKey: Data?
        let receivingChainKey: Data?
        let sendRatchetKeyPrivate: Data
        let recvRatchetPublicKey: Data?
        let sendMessageNumber: UInt32
        let recvMessageNumber: UInt32
        let previousSendChainLength: UInt32
    }

    public func exportState() -> SessionState {
        SessionState(
            rootKey: rootKey.dataRepresentation,
            sendingChainKey: sendingChainKey?.dataRepresentation,
            receivingChainKey: receivingChainKey?.dataRepresentation,
            sendRatchetKeyPrivate: sendRatchetKey.rawRepresentation,
            recvRatchetPublicKey: recvRatchetPublicKey?.rawRepresentation,
            sendMessageNumber: sendMessageNumber,
            recvMessageNumber: recvMessageNumber,
            previousSendChainLength: previousSendChainLength
        )
    }

    // MARK: — KDF Functions

    private static func kdfRootKey(
        rootKey: SymmetricKey,
        dhOutput: SharedSecret
    ) -> (SymmetricKey, SymmetricKey) {
        var dhData = Data()
        dhOutput.withUnsafeBytes { dhData.append(contentsOf: $0) }

        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: dhData),
            salt: rootKey.dataRepresentation,
            info: Data("SecureChat_Ratchet_v1".utf8),
            outputByteCount: 64
        )

        return derived.withUnsafeBytes { bytes in
            let rootData = Data(bytes.prefix(32))
            let chainData = Data(bytes.suffix(32))
            return (SymmetricKey(data: rootData), SymmetricKey(data: chainData))
        }
    }

    private static func kdfDeriveChain(from key: SymmetricKey, label: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            info: Data(label.utf8),
            outputByteCount: 32
        )
    }

    private static func kdfMessageKey(chainKey: SymmetricKey) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: chainKey,
            info: Data("SecureChat_MsgKey".utf8),
            outputByteCount: 32
        )
    }

    private static func kdfAdvanceChain(chainKey: SymmetricKey) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: chainKey,
            info: Data("SecureChat_ChainAdv".utf8),
            outputByteCount: 32
        )
    }
}

// MARK: — Helpers

extension SymmetricKey {
    var dataRepresentation: Data {
        withUnsafeBytes { Data($0) }
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
