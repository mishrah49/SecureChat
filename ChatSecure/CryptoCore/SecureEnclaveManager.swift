// CryptoCore/SecureEnclaveManager.swift
// SecureChat — Hardware-backed identity key management
//
// The Secure Enclave (SE) stores the device's long-term identity key (P-256).
// This key NEVER leaves the hardware chip — all signing happens inside the enclave.
// We persist only a reference (dataRepresentation), not actual private key bytes.

import Foundation
import CryptoKit
import Security
import OSLog

// MARK: — Errors

public enum SecureEnclaveError: Error, LocalizedError {
    case enclaveNotAvailable
    case keyGenerationFailed(OSStatus)
    case keyNotFound
    case keychainError(OSStatus)
    case signingFailed(Error)
    case invalidPublicKey

    public var errorDescription: String? {
        switch self {
        case .enclaveNotAvailable:
            return "Secure Enclave is not available on this device"
        case .keyGenerationFailed(let status):
            return "Key generation failed: \(status)"
        case .keyNotFound:
            return "Identity key not found in Keychain"
        case .keychainError(let status):
            return "Keychain operation failed: \(status)"
        case .signingFailed(let error):
            return "Signing failed: \(error.localizedDescription)"
        case .invalidPublicKey:
            return "Invalid public key data"
        }
    }
}

// MARK: — Manager

public final class SecureEnclaveManager: Sendable {

    private let identityKeyTag: String
    private let logger = Logger(subsystem: "com.securechat", category: "SecureEnclave")

    public init(keyTag: String = "com.securechat.identity.key") {
        self.identityKeyTag = keyTag
    }

    // MARK: — Hardware availability

    /// True if Secure Enclave hardware is present (false on Simulator)
    public var isAvailable: Bool {
        SecureEnclave.isAvailable
    }

    // MARK: — Key lifecycle

    /// Generate a new P-256 identity key inside the Secure Enclave.
    /// The key is bound to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`,
    /// meaning it cannot be extracted via backup/restore.
    @discardableResult
    public func generateIdentityKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard isAvailable else { throw SecureEnclaveError.enclaveNotAvailable }

        logger.info("Generating new SE identity key")

        // Remove any existing key first
        try? deleteIdentityKey()

        // Access control: key usable only when device is unlocked
        // Add .biometryCurrentSet here if you want Face ID per-sign
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            nil
        ) else {
            throw SecureEnclaveError.keyGenerationFailed(errSecParam)
        }

        // Generate inside SE
        let privateKey = try SecureEnclave.P256.Signing.PrivateKey(
            compactRepresentable: false,
            accessControl: accessControl
        )

        // Store the key reference in Keychain
        let query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrAccount as String:    identityKeyTag,
            kSecAttrService as String:    "com.securechat.crypto",
            kSecValueData as String:      privateKey.dataRepresentation,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureEnclaveError.keychainError(status)
        }

        logger.info("SE identity key generated and stored")
        return privateKey
    }

    /// Load existing identity key from Keychain → SE reference
    public func loadIdentityKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrAccount as String:  identityKeyTag,
            kSecAttrService as String:  "com.securechat.crypto",
            kSecReturnData as String:   true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw SecureEnclaveError.keyNotFound
        }

        // Reconstruct SE key from stored reference
        return try SecureEnclave.P256.Signing.PrivateKey(
            dataRepresentation: data
        )
    }

    /// Get existing key or create new one
    public func getOrCreateIdentityKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        do {
            return try loadIdentityKey()
        } catch SecureEnclaveError.keyNotFound {
            return try generateIdentityKey()
        }
    }

    // MARK: — Signing

    /// Sign arbitrary data with the SE identity key
    public func sign(_ data: Data) throws -> P256.Signing.ECDSASignature {
        do {
            let key = try loadIdentityKey()
            return try key.signature(for: data)
        } catch let error as SecureEnclaveError {
            throw error
        } catch {
            throw SecureEnclaveError.signingFailed(error)
        }
    }

    /// Sign a digest (pre-hashed data)
    public func sign(digest: SHA256Digest) throws -> P256.Signing.ECDSASignature {
        let key = try loadIdentityKey()
        return try key.signature(for: digest)
    }

    // MARK: — Public key export

    /// Raw public key bytes for sharing with other users / uploading to server
    public func publicKeyData() throws -> Data {
        let key = try loadIdentityKey()
        return key.publicKey.rawRepresentation
    }

    /// Compact DER-encoded public key (for wire format)
    public func publicKeyCompressed() throws -> Data {
        let key = try loadIdentityKey()
        return key.publicKey.compressedRepresentation
    }

    // MARK: — Verification (static — anyone can verify)

    /// Verify a signature against a public key
    public static func verify(
        signature: P256.Signing.ECDSASignature,
        data: Data,
        publicKey: Data
    ) throws -> Bool {
        let pubKey = try P256.Signing.PublicKey(rawRepresentation: publicKey)
        return pubKey.isValidSignature(signature, for: data)
    }

    // MARK: — Deletion

    public func deleteIdentityKey() throws {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrAccount as String:  identityKeyTag,
            kSecAttrService as String:  "com.securechat.crypto",
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw SecureEnclaveError.keychainError(status)
        }
        logger.info("SE identity key deleted")
    }

    /// Check if identity key exists without loading it
    public func hasIdentityKey() -> Bool {
        (try? loadIdentityKey()) != nil
    }
}
