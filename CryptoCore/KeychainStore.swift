// CryptoCore/KeychainStore.swift
// SecureChat — Keychain wrapper for persisting crypto keys
//
// The SE stores the P-256 identity key, but we also need to persist:
// - Curve25519 identity key pair (for X3DH)
// - Signed prekey pairs (rotated weekly)
// - One-time prekey pool
// - Double Ratchet session states
//
// All stored with kSecAttrAccessibleWhenUnlockedThisDeviceOnly
// (not backed up, not migrated to new device).

import Foundation
import Security
import CryptoKit

// MARK: — Errors

public enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case dataConversionFailed
    case itemNotFound

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let s): return "Keychain save failed: \(s)"
        case .loadFailed(let s): return "Keychain load failed: \(s)"
        case .deleteFailed(let s): return "Keychain delete failed: \(s)"
        case .dataConversionFailed: return "Data conversion failed"
        case .itemNotFound: return "Item not found in Keychain"
        }
    }
}

// MARK: — Keychain Store

public final class KeychainStore: Sendable {

    private let service: String

    public init(service: String = "com.securechat.keystore") {
        self.service = service
    }

    // MARK: — Generic Data Operations

    public func save(_ data: Data, forKey key: String) throws {
        // Delete existing item first
        try? delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    service,
            kSecAttrAccount as String:    key,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    public func load(forKey key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.loadFailed(status)
        }
        return data
    }

    public func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deleteFailed(status)
        }
    }

    public func exists(forKey key: String) -> Bool {
        (try? load(forKey: key)) != nil
    }

    // MARK: — Curve25519 Key Operations

    /// Save a Curve25519 key agreement private key
    public func saveCurve25519Key(
        _ key: Curve25519.KeyAgreement.PrivateKey,
        forKey keyId: String
    ) throws {
        try save(key.rawRepresentation, forKey: "curve25519.ka.\(keyId)")
    }

    /// Load a Curve25519 key agreement private key
    public func loadCurve25519Key(
        forKey keyId: String
    ) throws -> Curve25519.KeyAgreement.PrivateKey {
        let data = try load(forKey: "curve25519.ka.\(keyId)")
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    /// Save a Curve25519 signing private key
    public func saveCurve25519SigningKey(
        _ key: Curve25519.Signing.PrivateKey,
        forKey keyId: String
    ) throws {
        try save(key.rawRepresentation, forKey: "curve25519.sign.\(keyId)")
    }

    /// Load a Curve25519 signing private key
    public func loadCurve25519SigningKey(
        forKey keyId: String
    ) throws -> Curve25519.Signing.PrivateKey {
        let data = try load(forKey: "curve25519.sign.\(keyId)")
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    // MARK: — Session State Persistence

    /// Save a serialized Double Ratchet session state
    public func saveSessionState(
        _ state: DoubleRatchetSession.SessionState,
        forUser userId: String
    ) throws {
        let data = try JSONEncoder().encode(state)
        try save(data, forKey: "session.\(userId)")
    }

    /// Load a Double Ratchet session state
    public func loadSessionState(
        forUser userId: String
    ) throws -> DoubleRatchetSession.SessionState {
        let data = try load(forKey: "session.\(userId)")
        return try JSONDecoder().decode(DoubleRatchetSession.SessionState.self, from: data)
    }

    // MARK: — PreKey Management

    /// Save a batch of one-time prekey private keys
    public func saveOneTimePreKeys(
        _ keys: [Curve25519.KeyAgreement.PrivateKey],
        startingId: UInt32
    ) throws {
        for (offset, key) in keys.enumerated() {
            let id = startingId + UInt32(offset)
            try saveCurve25519Key(key, forKey: "otpk.\(id)")
        }
        // Save the count for management
        let countData = withUnsafeBytes(of: UInt32(keys.count)) { Data($0) }
        try save(countData, forKey: "otpk.count")
    }

    /// Load and consume a one-time prekey
    public func consumeOneTimePreKey(id: UInt32) throws -> Curve25519.KeyAgreement.PrivateKey {
        let key = try loadCurve25519Key(forKey: "otpk.\(id)")
        try delete(forKey: "curve25519.ka.otpk.\(id)")
        return key
    }

    // MARK: — Registration ID

    public func saveRegistrationId(_ id: UInt32) throws {
        let data = withUnsafeBytes(of: id) { Data($0) }
        try save(data, forKey: "registration.id")
    }

    public func loadRegistrationId() throws -> UInt32 {
        let data = try load(forKey: "registration.id")
        return data.withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    public func getOrCreateRegistrationId() throws -> UInt32 {
        do {
            return try loadRegistrationId()
        } catch KeychainError.itemNotFound {
            let id = UInt32.random(in: 1...UInt32(Int16.max))
            try saveRegistrationId(id)
            return id
        }
    }

    // MARK: — Wipe All Keys

    /// Nuclear option: delete all crypto material.
    /// Call on account deletion or security threat.
    public func wipeAll() throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deleteFailed(status)
        }
    }
}
