// CryptoCore/X3DH.swift
// SecureChat — X3DH (Extended Triple Diffie-Hellman) key agreement
//
// X3DH establishes a shared secret between two users who may be offline.
// Flow:
//   1. Bob publishes a PreKeyBundle to the server (identity key, signed prekey, one-time prekeys)
//   2. Alice fetches Bob's bundle and computes a shared secret using 3-4 DH operations
//   3. Alice sends her ephemeral public key + initial ciphertext to Bob
//   4. Bob reconstructs the same shared secret
//
// NOTE: SE uses P-256, but X3DH uses Curve25519 (CryptoKit.Curve25519).
// Bridge: The SE P-256 key signs the Curve25519 identity key for authentication.

import CryptoKit
import Foundation

// MARK: — Key Bundle (published to server)

/// A user's public key material, uploaded to the server so others can start sessions.
public struct PreKeyBundle: Codable, Sendable {
    /// Curve25519 identity public key (signed by SE P-256 key for authenticity)
    public let identityKey: Data
    /// SE signature over the identityKey (P-256 ECDSA)
    public let identityKeySignature: Data
    /// Curve25519 signed prekey (medium-term, rotated weekly)
    public let signedPreKey: Data
    /// Signature of signedPreKey using identityKey
    public let signedPreKeySignature: Data
    /// One-time prekey (consumed after one use, provides forward secrecy for first msg)
    public let oneTimePreKey: Data?
    /// Unique device registration id
    public let registrationId: UInt32

    public init(
        identityKey: Data,
        identityKeySignature: Data,
        signedPreKey: Data,
        signedPreKeySignature: Data,
        oneTimePreKey: Data?,
        registrationId: UInt32
    ) {
        self.identityKey = identityKey
        self.identityKeySignature = identityKeySignature
        self.signedPreKey = signedPreKey
        self.signedPreKeySignature = signedPreKeySignature
        self.oneTimePreKey = oneTimePreKey
        self.registrationId = registrationId
    }
}

// MARK: — X3DH Result

public struct X3DHResult: Sendable {
    /// The shared root key to initialize the Double Ratchet
    public let sharedSecret: SymmetricKey
    /// Alice's ephemeral public key (sent to Bob so he can reconstruct)
    public let ephemeralPublicKey: Data
    /// Whether a one-time prekey was used (if not, slightly weaker forward secrecy)
    public let usedOneTimePreKey: Bool
}

// MARK: — X3DH Errors

public enum X3DHError: Error, LocalizedError {
    case invalidPublicKey(String)
    case signatureVerificationFailed
    case keyAgreementFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidPublicKey(let which):
            return "Invalid \(which) public key"
        case .signatureVerificationFailed:
            return "PreKey signature verification failed — possible MITM"
        case .keyAgreementFailed(let error):
            return "Key agreement failed: \(error.localizedDescription)"
        }
    }
}

// MARK: — X3DH Protocol

public enum X3DH {

    // MARK: — Initiator (Alice) side

    /// Alice initiates a session with Bob using his published PreKeyBundle.
    ///
    /// - Parameters:
    ///   - myIdentityKey: Alice's Curve25519 identity private key
    ///   - theirBundle: Bob's PreKeyBundle fetched from server
    /// - Returns: Shared secret + ephemeral public key to send to Bob
    public static func initiateSession(
        myIdentityKey: Curve25519.KeyAgreement.PrivateKey,
        theirBundle: PreKeyBundle
    ) throws -> X3DHResult {

        // Parse Bob's public keys
        let theirIdentity: Curve25519.KeyAgreement.PublicKey
        let theirSignedPreKey: Curve25519.KeyAgreement.PublicKey

        do {
            theirIdentity = try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: theirBundle.identityKey
            )
        } catch {
            throw X3DHError.invalidPublicKey("identity")
        }

        do {
            theirSignedPreKey = try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: theirBundle.signedPreKey
            )
        } catch {
            throw X3DHError.invalidPublicKey("signedPreKey")
        }

        // Verify Bob's signed prekey signature using his identity key
        // (This ensures the prekey was actually published by Bob)
        let signingKey = try Curve25519.Signing.PublicKey(
            rawRepresentation: theirBundle.identityKey
        )
        let signatureValid = signingKey.isValidSignature(
            theirBundle.signedPreKeySignature,
            for: theirBundle.signedPreKey
        )
        guard signatureValid else {
            throw X3DHError.signatureVerificationFailed
        }

        // Generate ephemeral key pair (used only for this session)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()

        // Perform DH operations
        do {
            // DH1: myIdentity × theirSignedPreKey
            let dh1 = try myIdentityKey.sharedSecretFromKeyAgreement(with: theirSignedPreKey)
            // DH2: myEphemeral × theirIdentity
            let dh2 = try ephemeral.sharedSecretFromKeyAgreement(with: theirIdentity)
            // DH3: myEphemeral × theirSignedPreKey
            let dh3 = try ephemeral.sharedSecretFromKeyAgreement(with: theirSignedPreKey)

            // Concatenate DH outputs
            var combined = Data()
            // Prepend 32 bytes of 0xFF (protocol padding per Signal spec)
            combined.append(Data(repeating: 0xFF, count: 32))
            dh1.withUnsafeBytes { combined.append(contentsOf: $0) }
            dh2.withUnsafeBytes { combined.append(contentsOf: $0) }
            dh3.withUnsafeBytes { combined.append(contentsOf: $0) }

            // DH4: myEphemeral × theirOneTimePreKey (optional)
            var usedOTPK = false
            if let otpkData = theirBundle.oneTimePreKey {
                let otpk = try Curve25519.KeyAgreement.PublicKey(
                    rawRepresentation: otpkData
                )
                let dh4 = try ephemeral.sharedSecretFromKeyAgreement(with: otpk)
                dh4.withUnsafeBytes { combined.append(contentsOf: $0) }
                usedOTPK = true
            }

            // Derive root key via HKDF-SHA256
            let rootKey = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: combined),
                salt: Data("SecureChat_X3DH_v1".utf8),
                info: Data("root-key-derivation".utf8),
                outputByteCount: 32
            )

            return X3DHResult(
                sharedSecret: rootKey,
                ephemeralPublicKey: ephemeral.publicKey.rawRepresentation,
                usedOneTimePreKey: usedOTPK
            )
        } catch let error as X3DHError {
            throw error
        } catch {
            throw X3DHError.keyAgreementFailed(error)
        }
    }

    // MARK: — Responder (Bob) side

    /// Bob receives Alice's initial message and reconstructs the shared secret.
    ///
    /// - Parameters:
    ///   - myIdentityKey: Bob's Curve25519 identity private key
    ///   - mySignedPreKey: Bob's signed prekey private key
    ///   - myOneTimePreKey: The one-time prekey Alice used (if any)
    ///   - theirIdentityKey: Alice's Curve25519 identity public key
    ///   - theirEphemeralKey: Alice's ephemeral public key (from her initial message)
    /// - Returns: The same shared secret Alice computed
    public static func respondToSession(
        myIdentityKey: Curve25519.KeyAgreement.PrivateKey,
        mySignedPreKey: Curve25519.KeyAgreement.PrivateKey,
        myOneTimePreKey: Curve25519.KeyAgreement.PrivateKey?,
        theirIdentityKey: Data,
        theirEphemeralKey: Data
    ) throws -> SymmetricKey {

        let theirIdentity = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: theirIdentityKey
        )
        let theirEphemeral = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: theirEphemeralKey
        )

        // Mirror DH operations (swapped roles)
        // DH1: mySignedPreKey × theirIdentity
        let dh1 = try mySignedPreKey.sharedSecretFromKeyAgreement(with: theirIdentity)
        // DH2: myIdentity × theirEphemeral
        let dh2 = try myIdentityKey.sharedSecretFromKeyAgreement(with: theirEphemeral)
        // DH3: mySignedPreKey × theirEphemeral
        let dh3 = try mySignedPreKey.sharedSecretFromKeyAgreement(with: theirEphemeral)

        var combined = Data()
        combined.append(Data(repeating: 0xFF, count: 32))
        dh1.withUnsafeBytes { combined.append(contentsOf: $0) }
        dh2.withUnsafeBytes { combined.append(contentsOf: $0) }
        dh3.withUnsafeBytes { combined.append(contentsOf: $0) }

        // DH4 if one-time prekey was used
        if let otpk = myOneTimePreKey {
            let dh4 = try otpk.sharedSecretFromKeyAgreement(with: theirEphemeral)
            dh4.withUnsafeBytes { combined.append(contentsOf: $0) }
        }

        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: combined),
            salt: Data("SecureChat_X3DH_v1".utf8),
            info: Data("root-key-derivation".utf8),
            outputByteCount: 32
        )
    }

    // MARK: — PreKey Bundle Generation

    /// Generate a complete PreKeyBundle to upload to the server.
    ///
    /// - Parameters:
    ///   - seManager: SecureEnclaveManager for signing the Curve25519 identity key
    ///   - identityKey: Curve25519 identity key pair
    ///   - registrationId: Device registration id
    ///   - includeOneTimePreKey: Whether to include a one-time prekey
    /// - Returns: (PreKeyBundle for server, signedPreKeyPrivate for local storage)
    public static func generatePreKeyBundle(
        seManager: SecureEnclaveManager,
        identityKey: Curve25519.KeyAgreement.PrivateKey,
        registrationId: UInt32,
        includeOneTimePreKey: Bool = true
    ) throws -> (bundle: PreKeyBundle, signedPreKeyPrivate: Curve25519.KeyAgreement.PrivateKey, oneTimePreKeyPrivate: Curve25519.KeyAgreement.PrivateKey?) {

        let identityPubData = identityKey.publicKey.rawRepresentation

        // Sign the Curve25519 identity key with SE P-256 key
        // This bridges SE hardware trust to the X3DH identity
        let identitySig = try seManager.sign(identityPubData)

        // Generate signed prekey
        let signedPreKey = Curve25519.KeyAgreement.PrivateKey()
        let signedPreKeyPub = signedPreKey.publicKey.rawRepresentation

        // Sign the prekey with identity key (Curve25519 signing key)
        let signingKey = try Curve25519.Signing.PrivateKey(
            rawRepresentation: identityKey.rawRepresentation
        )
        let signedPreKeySig = try signingKey.signature(for: signedPreKeyPub)

        // Optional one-time prekey
        var otpk: Curve25519.KeyAgreement.PrivateKey?
        var otpkPub: Data?
        if includeOneTimePreKey {
            let key = Curve25519.KeyAgreement.PrivateKey()
            otpk = key
            otpkPub = key.publicKey.rawRepresentation
        }

        let bundle = PreKeyBundle(
            identityKey: identityPubData,
            identityKeySignature: identitySig.rawRepresentation,
            signedPreKey: signedPreKeyPub,
            signedPreKeySignature: signedPreKeySig,
            oneTimePreKey: otpkPub,
            registrationId: registrationId
        )

        return (bundle, signedPreKey, otpk)
    }
}
