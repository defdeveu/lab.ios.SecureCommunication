import CryptoKit
import Foundation
import Security

struct ResponseContext: @unchecked Sendable {
    // Internal rather than public: the production UI never receives key bytes,
    // while @testable unit tests can construct deterministic response fixtures.
    let symmetricKey: SymmetricKey
    let requestID: String
}

struct SealedRequest: Sendable {
    let body: Data
    let responseContext: ResponseContext
}

protocol SecureEnvelopeCryptoProtocol: Sendable {
    func seal(message: String) throws -> SealedRequest
    func openResponse(_ data: Data, context: ResponseContext) throws -> ResponsePlaintext
}

// SecureEnvelopeCrypto combines modern platform primitives into the lab's
// explicit wire protocol. It does not attempt to replace HTTPS: URLSession must
// still establish an ordinarily trusted TLS connection before these bytes are
// exchanged.
final class SecureEnvelopeCrypto: SecureEnvelopeCryptoProtocol, @unchecked Sendable {
    private let keys: ApplicationKeys
    private let now: @Sendable () -> Date
    private let makeRequestID: @Sendable () -> UUID

    init(
        keys: ApplicationKeys,
        now: @escaping @Sendable () -> Date = { Date() },
        makeRequestID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.keys = keys
        self.now = now
        self.makeRequestID = makeRequestID
    }

    func seal(message: String) throws -> SealedRequest {
        guard message.lengthOfBytes(using: .utf8) <= SecureProtocolConstants.maximumMessageBytes else {
            throw SecureProtocolError.messageTooLarge
        }

        let requestID = makeRequestID().uuidString.lowercased()
        let plaintext = RequestPlaintext(
            requestID: requestID,
            sentAt: Int64(now().timeIntervalSince1970),
            message: message
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plaintextData = try encoder.encode(plaintext)

        // A new random key and nonce for every send ensure equal messages do
        // not produce equal ciphertext. CryptoKit generates the nonce when nil.
        let symmetricKey = SymmetricKey(size: .bits256)
        let sealedMessage = try AES.GCM.seal(
            plaintextData,
            using: symmetricKey,
            authenticating: SecureProtocolConstants.requestAuthenticatedData
        )
        let keyData = symmetricKey.withUnsafeBytes { Data($0) }
        guard keyData.count == SecureProtocolConstants.aesKeyBytes else {
            throw SecureProtocolError.encryptionFailed
        }

        let encryptionAlgorithm: SecKeyAlgorithm = .rsaEncryptionOAEPSHA256
        guard SecKeyIsAlgorithmSupported(keys.serverPublicKey, .encrypt, encryptionAlgorithm) else {
            throw SecureProtocolError.unsupportedAlgorithm("RSA-OAEP-SHA256 encryption")
        }
        var encryptionError: Unmanaged<CFError>?
        guard let encryptedKey = SecKeyCreateEncryptedData(
            keys.serverPublicKey,
            encryptionAlgorithm,
            keyData as CFData,
            &encryptionError
        ) as Data? else {
            _ = encryptionError?.takeRetainedValue()
            throw SecureProtocolError.encryptionFailed
        }

        let nonce = sealedMessage.nonce.withUnsafeBytes { Data($0) }
        let ciphertext = sealedMessage.ciphertext
        let tag = sealedMessage.tag
        let signedData = try CanonicalSignatureInput.make(
            encryptedKey: encryptedKey,
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )

        // The "Message" SecKey algorithm hashes signedData with SHA-256 before
        // applying RSA-PSS. Go independently hashes the same canonical bytes and
        // verifies the resulting digest with rsa.VerifyPSS.
        let signatureAlgorithm: SecKeyAlgorithm = .rsaSignatureMessagePSSSHA256
        guard SecKeyIsAlgorithmSupported(keys.clientPrivateKey, .sign, signatureAlgorithm) else {
            throw SecureProtocolError.unsupportedAlgorithm("RSA-PSS-SHA256 signing")
        }
        var signatureError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            keys.clientPrivateKey,
            signatureAlgorithm,
            signedData as CFData,
            &signatureError
        ) as Data? else {
            _ = signatureError?.takeRetainedValue()
            throw SecureProtocolError.signatureFailed
        }

        let envelope = RequestEnvelope(
            version: SecureProtocolConstants.version,
            encryptedKey: encryptedKey.base64EncodedString(),
            nonce: nonce.base64EncodedString(),
            ciphertext: ciphertext.base64EncodedString(),
            tag: tag.base64EncodedString(),
            signature: signature.base64EncodedString()
        )
        return SealedRequest(
            body: try encoder.encode(envelope),
            responseContext: ResponseContext(symmetricKey: symmetricKey, requestID: requestID)
        )
    }

    func openResponse(_ data: Data, context: ResponseContext) throws -> ResponsePlaintext {
        let envelope: ResponseEnvelope = try decodeExactJSONObject(
            data,
            keys: ["version", "nonce", "ciphertext", "tag"]
        )
        guard envelope.version == SecureProtocolConstants.version,
              let nonceData = Data(base64Encoded: envelope.nonce),
              nonceData.count == SecureProtocolConstants.nonceBytes,
              let ciphertext = Data(base64Encoded: envelope.ciphertext),
              !ciphertext.isEmpty,
              let tag = Data(base64Encoded: envelope.tag),
              tag.count == SecureProtocolConstants.tagBytes
        else {
            throw SecureProtocolError.invalidResponse
        }

        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let plaintextData = try AES.GCM.open(
                sealedBox,
                using: context.symmetricKey,
                authenticating: SecureProtocolConstants.responseAuthenticatedData(
                    requestID: context.requestID
                )
            )
            let response: ResponsePlaintext = try decodeExactJSONObject(
                plaintextData,
                keys: ["request_id", "code", "receipt_id", "message"]
            )
            guard response.requestID == context.requestID,
                  UUID(uuidString: response.receiptID) != nil
            else {
                throw SecureProtocolError.mismatchedRequest
            }
            return response
        } catch let error as SecureProtocolError {
            throw error
        } catch {
            throw SecureProtocolError.responseAuthenticationFailed
        }
    }

    // JSONDecoder deliberately ignores unknown keys. For a versioned security
    // envelope, silently accepting misspelled or unauthenticated fields is
    // confusing, so inspect the object keys before normal Codable decoding.
    private func decodeExactJSONObject<Value: Decodable>(
        _ data: Data,
        keys expectedKeys: Set<String>
    ) throws -> Value {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              Set(dictionary.keys) == expectedKeys,
              let decoded = try? JSONDecoder().decode(Value.self, from: data)
        else {
            throw SecureProtocolError.invalidResponse
        }
        return decoded
    }
}

// AppRepository uses this implementation only when configuration or bundled
// key loading failed. Keeping the failure inside the same protocol lets the UI
// remain inspectable and display a useful setup error instead of crashing.
final class UnavailableEnvelopeCrypto: SecureEnvelopeCryptoProtocol, @unchecked Sendable {
    private let message: String

    init(message: String) {
        self.message = message
    }

    func seal(message _: String) throws -> SealedRequest {
        throw UnavailableEnvelopeCryptoError(message: message)
    }

    func openResponse(_: Data, context _: ResponseContext) throws -> ResponsePlaintext {
        throw UnavailableEnvelopeCryptoError(message: message)
    }
}

struct UnavailableEnvelopeCryptoError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}
