// NetworkLayer/WebSocketManager.swift
// SecureChat — Secure WebSocket transport
//
// Persistent connection with:
// - Certificate pinning (SHA-256 pin of server cert)
// - Exponential backoff reconnection
// - Heartbeat keep-alive
// - All traffic is encrypted ciphertext — server sees nothing

import Foundation
import CryptoKit
import OSLog

// MARK: — Connection State

public enum ConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
}

// MARK: — WebSocket Manager

public actor WebSocketManager {

    // MARK: — Properties

    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private let serverURL: URL
    private let pinningDelegate: CertificatePinningDelegate
    private let logger = Logger(subsystem: "com.securechat", category: "WebSocket")

    private(set) var state: ConnectionState = .disconnected
    private var messageHandler: (@Sendable (Data) -> Void)?
    private var stateHandler: (@Sendable (ConnectionState) -> Void)?
    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    private var authToken: String?

    private let maxReconnectAttempts = 10
    private let heartbeatInterval: TimeInterval = 25  // seconds

    // MARK: — Init

    /// - Parameters:
    ///   - serverURL: WebSocket server URL (wss://...)
    ///   - pinnedCertHash: SHA-256 hash of the server's certificate (hex string)
    public init(serverURL: URL, pinnedCertHash: String) {
        self.serverURL = serverURL
        self.pinningDelegate = CertificatePinningDelegate(pinnedHash: pinnedCertHash)
    }

    // MARK: — Connect

    /// Establish authenticated WebSocket connection.
    ///
    /// - Parameters:
    ///   - authToken: JWT bearer token
    ///   - onMessage: Called with raw data for every incoming message
    ///   - onStateChange: Called when connection state changes
    public func connect(
        authToken: String,
        onMessage: @escaping @Sendable (Data) -> Void,
        onStateChange: (@Sendable (ConnectionState) -> Void)? = nil
    ) {
        guard case .disconnected = state else {
            logger.warning("Already connected or connecting")
            return
        }

        self.authToken = authToken
        self.messageHandler = onMessage
        self.stateHandler = onStateChange
        updateState(.connecting)

        var request = URLRequest(url: serverURL)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        session = URLSession(
            configuration: .ephemeral, // No caching
            delegate: pinningDelegate,
            delegateQueue: nil
        )

        socket = session?.webSocketTask(with: request)
        socket?.maximumMessageSize = 1 * 1024 * 1024 // 1MB max
        socket?.resume()

        updateState(.connected)
        logger.info("WebSocket connected to \(self.serverURL.host ?? "unknown")")

        startListening()
        startHeartbeat()
    }

    // MARK: — Send

    /// Send an encrypted message to a recipient.
    /// The server only sees the encrypted blob and recipientId.
    public func send(_ encryptedMessage: EncryptedMessage, to recipientId: String) async throws {
        let envelope = WireEnvelope(
            type: .message,
            recipientId: recipientId,
            payload: encryptedMessage,
            timestamp: Date().timeIntervalSince1970
        )
        let data = try JSONEncoder().encode(envelope)
        try await socket?.send(.data(data))
        logger.debug("Sent encrypted message to \(recipientId)")
    }

    /// Send a delivery receipt.
    public func sendReceipt(messageId: String, to recipientId: String, type: ReceiptType) async throws {
        let receipt = WireReceipt(
            type: type,
            messageId: messageId,
            recipientId: recipientId,
            timestamp: Date().timeIntervalSince1970
        )
        let data = try JSONEncoder().encode(receipt)
        try await socket?.send(.data(data))
    }

    // MARK: — Receive Loop

    private func startListening() {
        listenTask?.cancel()
        listenTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    guard let message = try await self.socket?.receive() else {
                        break
                    }
                    switch message {
                    case .data(let data):
                        await self.messageHandler?(data)
                    case .string(let text):
                        if let data = text.data(using: .utf8) {
                            await self.messageHandler?(data)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    await self.logger.error("WebSocket receive error: \(error.localizedDescription)")
                    await self.handleDisconnect()
                    break
                }
            }
        }
    }

    // MARK: — Heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(heartbeatInterval * 1_000_000_000))

                guard case .connected = await self.state else { break }

                do {
                    try await self.socket?.sendPing { error in
                        if let error {
                            Task { await self.logger.warning("Ping failed: \(error.localizedDescription)") }
                        }
                    }
                } catch {
                    await self.handleDisconnect()
                    break
                }
            }
        }
    }

    // MARK: — Reconnection

    private func handleDisconnect() {
        guard case .connected = state else { return }

        socket?.cancel(with: .goingAway, reason: nil)
        stopTasks()
        updateState(.disconnected)

        logger.info("Disconnected — starting reconnection")
        startReconnect()
    }

    private func startReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            var delay: UInt64 = 1

            for attempt in 1...maxReconnectAttempts {
                guard !Task.isCancelled else { return }

                await self.updateState(.reconnecting(attempt: attempt))
                await self.logger.info("Reconnect attempt \(attempt)/\(self.maxReconnectAttempts)")

                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)

                // Try to reconnect
                if let token = await self.authToken,
                   let handler = await self.messageHandler {
                    await self.resetConnection()
                    await self.connect(authToken: token, onMessage: handler, onStateChange: await self.stateHandler)

                    if case .connected = await self.state {
                        await self.logger.info("Reconnected on attempt \(attempt)")
                        return
                    }
                }

                // Exponential backoff: 1, 2, 4, 8, 16, 32, 60, 60, 60, 60
                delay = min(delay * 2, 60)
            }

            await self.logger.error("Max reconnect attempts reached")
            await self.updateState(.disconnected)
        }
    }

    // MARK: — Disconnect

    public func disconnect() {
        logger.info("Disconnecting WebSocket")
        reconnectTask?.cancel()
        stopTasks()
        socket?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        socket = nil
        session = nil
        updateState(.disconnected)
    }

    private func stopTasks() {
        listenTask?.cancel()
        heartbeatTask?.cancel()
    }

    private func resetConnection() {
        socket?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        socket = nil
        session = nil
    }

    private func updateState(_ newState: ConnectionState) {
        state = newState
        stateHandler?(newState)
    }
}

// MARK: — Certificate Pinning Delegate

final class CertificatePinningDelegate: NSObject, URLSessionDelegate, Sendable {

    let pinnedHash: String

    init(pinnedHash: String) {
        self.pinnedHash = pinnedHash
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {

        guard challenge.protectionSpace.authenticationMethod
                == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            return (.cancelAuthenticationChallenge, nil)
        }

        // Extract leaf certificate
        guard let certChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let serverCert = certChain.first
        else {
            return (.cancelAuthenticationChallenge, nil)
        }

        // Hash the certificate with SHA-256
        let serverData = SecCertificateCopyData(serverCert) as Data
        let hash = SHA256.hash(data: serverData)
        let serverHash = hash.compactMap { String(format: "%02x", $0) }.joined()

        // Compare against pinned hash
        if serverHash == pinnedHash.lowercased() {
            return (.useCredential, URLCredential(trust: trust))
        }

        // Pin mismatch — possible MITM attack
        return (.cancelAuthenticationChallenge, nil)
    }
}

// MARK: — Wire Format

/// Envelope for messages sent over the wire
struct WireEnvelope: Codable, Sendable {
    let type: WireMessageType
    let recipientId: String
    let payload: EncryptedMessage
    let timestamp: TimeInterval
}

enum WireMessageType: String, Codable, Sendable {
    case message
    case keyExchange
    case preKeyMessage
}

public enum ReceiptType: String, Codable, Sendable {
    case delivered
    case read
}

struct WireReceipt: Codable, Sendable {
    let type: ReceiptType
    let messageId: String
    let recipientId: String
    let timestamp: TimeInterval
}
