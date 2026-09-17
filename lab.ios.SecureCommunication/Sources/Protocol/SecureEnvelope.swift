import Foundation

enum SecureProtocolConstants {
    static let version = 1
    static let aesKeyBytes = 32
    static let nonceBytes = 12
    static let tagBytes = 16
    static let maximumMessageBytes = 4 * 1024

    // Domain separation prevents a byte sequence authenticated for one role
    // from being reused as another protocol object. These values are public
    // protocol constants and must match the Go server exactly.
    static let requestAuthenticatedData = Data(
        "hipinseco/secure-communication/request/v1".utf8
    )
    static let requestSignatureDomain = Data(
        "hipinseco/secure-communication/request-signature/v1\0".utf8
    )

    static func responseAuthenticatedData(requestID: String) -> Data {
        Data("hipinseco/secure-communication/response/v1/\(requestID)".utf8)
    }
}

// These outer types are intentionally boring Codable structures. JSON is only
// transport framing: signatures cover the decoded binary fields, so whitespace
// and dictionary key ordering cannot change the authenticated meaning.
struct RequestEnvelope: Codable, Equatable, Sendable {
    let version: Int
    let encryptedKey: String
    let nonce: String
    let ciphertext: String
    let tag: String
    let signature: String

    enum CodingKeys: String, CodingKey {
        case version
        case encryptedKey = "encrypted_key"
        case nonce
        case ciphertext
        case tag
        case signature
    }
}

struct ResponseEnvelope: Codable, Equatable, Sendable {
    let version: Int
    let nonce: String
    let ciphertext: String
    let tag: String
}

struct RequestPlaintext: Codable, Equatable, Sendable {
    let requestID: String
    let sentAt: Int64
    let message: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case sentAt = "sent_at"
        case message
    }
}

struct ResponsePlaintext: Codable, Equatable, Sendable {
    let requestID: String
    let code: Int
    let receiptID: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case code
        case receiptID = "receipt_id"
        case message
    }
}

enum CanonicalSignatureInput {
    // Each binary field is preceded by a four-byte unsigned big-endian length.
    // Without lengths, concatenations such as ["ab", "c"] and ["a", "bc"]
    // would be indistinguishable. This small framing rule is shared with Go and
    // deliberately avoids signing JSON serialization details.
    static func make(
        encryptedKey: Data,
        nonce: Data,
        ciphertext: Data,
        tag: Data
    ) throws -> Data {
        var result = SecureProtocolConstants.requestSignatureDomain
        for field in [encryptedKey, nonce, ciphertext, tag] {
            guard field.count <= Int(UInt32.max) else {
                throw SecureProtocolError.fieldTooLarge
            }
            result.appendBigEndian(UInt32(field.count))
            result.append(field)
        }
        return result
    }
}

extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        var encoded = value.bigEndian
        Swift.withUnsafeBytes(of: &encoded) { bytes in
            append(contentsOf: bytes)
        }
    }
}

enum SecureProtocolError: LocalizedError, Equatable {
    case fieldTooLarge
    case messageTooLarge
    case invalidKey(String)
    case unsupportedAlgorithm(String)
    case encryptionFailed
    case signatureFailed
    case invalidResponse
    case responseAuthenticationFailed
    case mismatchedRequest

    var errorDescription: String? {
        switch self {
        case .fieldTooLarge:
            "A protocol field is too large to encode."
        case .messageTooLarge:
            "The message must be at most \(SecureProtocolConstants.maximumMessageBytes) UTF-8 bytes."
        case let .invalidKey(name):
            "The bundled \(name) key is missing or invalid."
        case let .unsupportedAlgorithm(operation):
            "The bundled RSA key does not support \(operation)."
        case .encryptionFailed:
            "The request could not be encrypted."
        case .signatureFailed:
            "The request could not be signed."
        case .invalidResponse:
            "The server returned an invalid encrypted envelope."
        case .responseAuthenticationFailed:
            "The encrypted response failed authentication."
        case .mismatchedRequest:
            "The response belongs to a different request."
        }
    }
}
