// Services/CryptoService.swift
// SecureChat — High-level encryption service
//
// This is the integration layer. It orchestrates:
// - Secure Enclave (identity)
// - X3DH (session establishment)
// - Double Ratchet (message encryption)
// - Keychain (key persistence)
// - Security checks (runtime integrity)
//
// The ChatViewModel calls this service — it never touches crypto directly.

import Foundation
import CryptoKit
import OSLog

// MARK: — Errors

public enum CryptoServiceError: Error, LocalizedError {
    case notInitialized
    case noSessionForUser(String)
    case sessionCreationFailed(Error)
    case encryptionFailed(Error)
    case decryptionFailed(Error)
    case deviceCompromised(SecurityAuditResult)
    case preKeyBundleFetchFailed

    public var errorDescription: String? {
        switch self {
        case .notInitialized: return "CryptoService not initialized"
        case .noSessionForUser(let id): return "No encryption session for user \(id)"
        case .sessionCreationFailed(let e): return "Session creation failed: \(e.localizedDescription)"
        case .encryptionFailed(let e): return "Encryption failed: \(e.localizedDescription)"
        case .decryptionFailed(let e): return "Decryption failed: \(e.localizedDescription)"
        case .deviceCompromised(let r): return "Device security: \(r.threatLevel.rawValue)"
        case .preKeyBundleFetchFailed: return "Failed to fetch recipient's key bundle"
        }
    }
}

// MARK: — CryptoService

public actor CryptoService {

    // MARK: — Dependencies

    private let seManager: SecureEnclaveManager
    private let keychain: KeychainStore
    private let logger = Logger(subsystem: "com.securechat", category: "CryptoService")

    /// Curve25519 identity key pair (persisted in Keychain, NOT SE)
    /// SE stores P-256; this is the X3DH identity signed by SE for authentication
    private var identityKey: Curve25519.KeyAgreement.PrivateKey?

    /// Active ratchet sessions per user
    private var sessions: [String: DoubleRatchetSession] = [:]

    /// Device registration id
    private var registrationId: UInt32?

    /// Is the service bootstrapped?
    private var isReady = false

    // MARK: — Init

    public init(
        seManager: SecureEnclaveManager = SecureEnclaveManager(),
        keychain: KeychainStore = KeychainStore()
    ) {
        self.seManager = seManager
        self.keychain = keychain
    }

    // MARK: — Bootstrap (call on app launch)

    /// Initialize all crypto material.
    /// Call once at app launch after security audit passes.
    ///
    /// Flow:
    /// 1. Security audit
    /// 2. Get or create SE identity key (P-256, hardware)
    /// 3. Get or create Curve25519 identity key (software, signed by SE)
    /// 4. Get or create registration id
    /// 5. Load persisted ratchet sessions
    public func bootstrap() async throws {
        logger.info("Bootstrapping CryptoService...")

        // Step 1: Security audit
        let audit = SecurityCheck.performFullAudit()
        logger.info("Security audit: \(audit.threatLevel.rawValue)")

        if audit.threatLevel == .critical {
            throw CryptoServiceError.deviceCompromised(audit)
        }

        // Step 2: Secure Enclave identity key
        if seManager.isAvailable {
            _ = try seManager.getOrCreateIdentityKey()
            logger.info("SE identity key ready")
        } else {
            logger.warning("Secure Enclave not available — degraded security")
        }

        // Step 3: Curve25519 identity key
        identityKey = try loadOrCreateIdentityKey()
        logger.info("Curve25519 identity key ready")

        // Step 4: Registration id
        registrationId = try keychain.getOrCreateRegistrationId()

        // Step 5: Load any persisted sessions
        // (In production, iterate over known contacts and load sessions)

        isReady = true
        logger.info("CryptoService bootstrap complete")
    }

    // MARK: — Key Management

    private func loadOrCreateIdentityKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        do {
            return try keychain.loadCurve25519Key(forKey: "identity")
        } catch KeychainError.itemNotFound {
            let newKey = Curve25519.KeyAgreement.PrivateKey()
            try keychain.saveCurve25519Key(newKey, forKey: "identity")
            logger.info("Generated new Curve25519 identity key")
            return newKey
        }
    }

    /// Generate a PreKeyBundle for uploading to the server.
    /// Other users fetch this to start a session with us.
    public func generatePreKeyBundle() throws -> PreKeyBundle {
        guard let identityKey, let registrationId else {
            throw CryptoServiceError.notInitialized
        }

        let (bundle, signedPreKeyPrivate, otpkPrivate) = try X3DH.generatePreKeyBundle(
            seManager: seManager,
            identityKey: identityKey,
            registrationId: registrationId,
            includeOneTimePreKey: true
        )

        // Persist signed prekey private
        try keychain.saveCurve25519Key(signedPreKeyPrivate, forKey: "signed_prekey.current")

        // Persist one-time prekey if generated
        if let otpk = otpkPrivate {
            try keychain.saveCurve25519Key(otpk, forKey: "otpk.latest")
        }

        logger.info("Generated PreKeyBundle (regId: \(registrationId))")
        return bundle
    }

    /// Generate a batch of one-time prekeys for replenishment.
    public func generateOneTimePreKeys(count: Int = 50) throws -> [Data] {
        var publicKeys: [Data] = []
        var privateKeys: [Curve25519.KeyAgreement.PrivateKey] = []

        for _ in 0..<count {
            let key = Curve25519.KeyAgreement.PrivateKey()
            privateKeys.append(key)
            publicKeys.append(key.publicKey.rawRepresentation)
        }

        // Persist private keys
        let startId = UInt32.random(in: 1000...UInt32.max - UInt32(count))
        try keychain.saveOneTimePreKeys(privateKeys, startingId: startId)

        logger.info("Generated \(count) one-time prekeys")
        return publicKeys
    }

    // MARK: — Session Establishment

    /// Initiate a new session with a remote user using their PreKeyBundle.
    /// Call when sending the FIRST message to someone new.
    public func initiateSession(
        withUser userId: String,
        theirBundle: PreKeyBundle
    ) throws {
        guard let identityKey else {
            throw CryptoServiceError.notInitialized
        }

        do {
            // X3DH key agreement
            let result = try X3DH.initiateSession(
                myIdentityKey: identityKey,
                theirBundle: theirBundle
            )

            // Parse their signed prekey as the initial ratchet key
            let theirRatchetKey = try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: theirBundle.signedPreKey
            )

            // Initialize Double Ratchet with the X3DH shared secret
            let session = try DoubleRatchetSession(
                sharedSecret: result.sharedSecret,
                remoteRatchetKey: theirRatchetKey,
                isInitiator: true
            )

            sessions[userId] = session
            logger.info("Session initiated with \(userId) (OTPK: \(result.usedOneTimePreKey))")
        } catch {
            throw CryptoServiceError.sessionCreationFailed(error)
        }
    }

    /// Handle an incoming session from a remote user.
    /// Call when receiving the FIRST message from someone new.
    public func acceptSession(
        fromUser userId: String,
        theirIdentityKey: Data,
        theirEphemeralKey: Data,
        usedOneTimePreKeyId: UInt32?
    ) throws {
        guard let identityKey else {
            throw CryptoServiceError.notInitialized
        }

        do {
            let signedPreKey = try keychain.loadCurve25519Key(forKey: "signed_prekey.current")

            var otpk: Curve25519.KeyAgreement.PrivateKey?
            if let otpkId = usedOneTimePreKeyId {
                otpk = try keychain.consumeOneTimePreKey(id: otpkId)
            }

            let sharedSecret = try X3DH.respondToSession(
                myIdentityKey: identityKey,
                mySignedPreKey: signedPreKey,
                myOneTimePreKey: otpk,
                theirIdentityKey: theirIdentityKey,
                theirEphemeralKey: theirEphemeralKey
            )

            let session = try DoubleRatchetSession(
                sharedSecret: sharedSecret,
                isInitiator: false
            )

            sessions[userId] = session
            logger.info("Session accepted from \(userId)")
        } catch {
            throw CryptoServiceError.sessionCreationFailed(error)
        }
    }

    // MARK: — Message Encryption / Decryption

    /// Encrypt a plaintext message for a specific user.
    public func encrypt(
        _ plaintext: String,
        forUser userId: String
    ) async throws -> EncryptedMessage {
        guard let session = sessions[userId] else {
            throw CryptoServiceError.noSessionForUser(userId)
        }

        guard let data = plaintext.data(using: .utf8) else {
            throw CryptoServiceError.encryptionFailed(
                NSError(domain: "crypto", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "UTF-8 encoding failed"])
            )
        }

        do {
            let encrypted = try await session.encrypt(data)
            logger.debug("Encrypted message for \(userId) (#\(encrypted.messageNumber))")
            return encrypted
        } catch {
            throw CryptoServiceError.encryptionFailed(error)
        }
    }

    /// Decrypt a received message from a specific user.
    public func decrypt(
        _ message: EncryptedMessage,
        fromUser userId: String
    ) async throws -> String {
        guard let session = sessions[userId] else {
            throw CryptoServiceError.noSessionForUser(userId)
        }

        do {
            let plainData = try await session.decrypt(message)
            guard let text = String(data: plainData, encoding: .utf8) else {
                throw CryptoServiceError.decryptionFailed(
                    NSError(domain: "crypto", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "UTF-8 decoding failed"])
                )
            }
            logger.debug("Decrypted message from \(userId) (#\(message.messageNumber))")
            return text
        } catch {
            throw CryptoServiceError.decryptionFailed(error)
        }
    }

    // MARK: — Session Management

    /// Check if we have an active session with a user
    public func hasSession(forUser userId: String) -> Bool {
        sessions[userId] != nil
    }

    /// Persist all session states to Keychain (call on app background)
    public func persistAllSessions() async throws {
        for (userId, session) in sessions {
            let state = await session.exportState()
            try keychain.saveSessionState(state, forUser: userId)
        }
        logger.info("Persisted \(self.sessions.count) session(s)")
    }

    /// Remove session for a user (on block / account delete)
    public func removeSession(forUser userId: String) {
        sessions.removeValue(forKey: userId)
        try? keychain.delete(forKey: "session.\(userId)")
        logger.info("Removed session for \(userId)")
    }

    // MARK: — Identity

    /// Get our public identity info for sharing
    public func myPublicIdentity() throws -> (identityKey: Data, sePublicKey: Data?) {
        guard let identityKey else {
            throw CryptoServiceError.notInitialized
        }

        let seKey = try? seManager.publicKeyData()
        return (identityKey.publicKey.rawRepresentation, seKey)
    }

    // MARK: — Wipe

    /// Delete ALL crypto material — nuclear option.
    /// Use on account deletion or critical security threat.
    public func wipeEverything() throws {
        sessions.removeAll()
        try? seManager.deleteIdentityKey()
        try keychain.wipeAll()
        identityKey = nil
        registrationId = nil
        isReady = false
        logger.warning("All crypto material wiped")
    }
}
