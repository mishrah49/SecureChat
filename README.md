# 🔒 SecureChat: Hardware-Secured Serverless IM

SecureChat is a proof-of-concept Instant Messaging (IM) architecture designed for maximum privacy. It bypasses traditional centralized database servers, leveraging the **iOS Secure Enclave** for hardware-backed cryptography, **Face ID** for biometric access control, and **AWS S3** as a serverless, peer-to-peer message broker.

## 🏗 System Architecture

The system operates without a traditional backend application server. iOS clients communicate directly with AWS infrastructure using temporary, tightly-scoped IAM credentials.

### Components
1. **iOS Client (Swift/SwiftUI):** Manages the user interface, biometric authentication (LocalAuthentication), and cryptographic operations (CryptoKit).
2. **Apple Secure Enclave:** A dedicated, isolated subsystem on the iPhone. It generates and stores the user's private keys. The keys *never* leave this chip.
3. **AWS S3 (Message Broker):** Private, shared buckets where encrypted JSON messages are deposited.
4. **AWS Cognito (Identity/Auth):** Exchanges user credentials for temporary, restricted AWS IAM roles that only permit access to specific S3 prefixes (chat rooms).
5. **AWS SNS/APNs (Notifications):** S3 bucket events trigger SNS, which formats and sends push notifications to Apple Push Notification service (APNs) to wake up the receiver's device.

---

## 🔐 Cryptographic Flow

Because the Secure Enclave is optimized for asymmetric cryptography (specifically Elliptic Curve `secp256r1`) and not bulk data encryption, the app uses a **Hybrid Encryption** model.

### 1. Key Generation & Exchange
* **Alice** opens the app. The Secure Enclave generates an Elliptic Curve (ECC) key pair.
* The **Private Key** is permanently locked inside the Secure Enclave. Accessing it requires a successful Face ID scan.
* The **Public Key** is exported and shared with **Bob** (via a secure out-of-band channel or a trusted AWS DynamoDB public key directory).

### 2. Message Encryption (Sending)
When Alice sends a message to Bob:
1. Alice's device generates a one-time symmetric key (AES-GCM-256).
2. The plain text message is encrypted using this AES key.
3. Alice's device performs Elliptic-Curve Diffie-Hellman (ECDH) key agreement using **her private key** (which requires Face ID authorization) and **Bob's public key** to derive a shared secret.
4. The AES one-time key is encrypted/wrapped using this shared secret.
5. The encrypted payload, wrapped key, and metadata are packaged into a JSON file.

### 3. Message Transmission
The JSON file is pushed directly to a shared, private AWS S3 bucket path: `s3://securechat-storage/chat-id-alice-bob/timestamp-uuid.json`.

### 4. Message Decryption (Receiving)
1. Bob receives a silent push notification via APNs that a new object was created in S3.
2. Bob's app downloads the JSON file.
3. Bob looks at his screen (Face ID authenticates).
4. Bob's Secure Enclave uses **his private key** and **Alice's public key** to compute the same ECDH shared secret.
5. The shared secret unwraps the AES one-time key.
6. The AES key decrypts the message payload.

---

## 📄 JSON Message Schema

All messages uploaded to S3 conform to the following JSON structure. **No plain text content is ever exposed to AWS.**

```json
{
  "messageId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "senderId": "alice_uid_8841",
  "timestamp": "2026-04-02T21:30:36Z",
  "cryptoContext": {
    "algorithm": "AES-GCM-256",
    "iv": "base64_encoded_initialization_vector",
    "ephemeralPublicKey": "base64_encoded_ephemeral_key_for_ecdh",
    "wrappedKey": "base64_encoded_encrypted_aes_key"
  },
  "payload": "base64_encoded_ciphertext_message_data",
  "ttl": 604800 
}
