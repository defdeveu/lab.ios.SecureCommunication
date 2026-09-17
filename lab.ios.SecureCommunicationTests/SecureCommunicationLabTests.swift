import CryptoKit
import Foundation
import Security
import XCTest
@testable import lab_ios_SecureCommunication

final class LabConfigurationTests: XCTestCase {
    func testParsesHostedEndpoint() throws {
        let configuration = try LabConfiguration.parse([
            "LabSecureCommunicationURL": "https://zsk.labs.def.dev/secure-communication/request",
        ])
        XCTAssertEqual(configuration.endpoint.scheme, "https")
        XCTAssertEqual(configuration.endpoint.host(), "zsk.labs.def.dev")
        XCTAssertEqual(configuration.endpoint.path(), "/secure-communication/request")
    }

    func testRejectsHTTPAndWrongPath() {
        XCTAssertThrowsError(try LabConfiguration.parse([
            "LabSecureCommunicationURL": "http://zsk.labs.def.dev/secure-communication/request",
        ]))
        XCTAssertThrowsError(try LabConfiguration.parse([
            "LabSecureCommunicationURL": "https://zsk.labs.def.dev/request",
        ]))
    }
}

final class SecureEnvelopeTests: XCTestCase {
    func testCanonicalSignatureInputMatchesGoVector() throws {
        let input = try CanonicalSignatureInput.make(
            encryptedKey: Data([1, 2]),
            nonce: Data([3]),
            ciphertext: Data([4, 5, 6]),
            tag: Data([7])
        )
        let digest = Data(SHA256.hash(data: input))
        XCTAssertEqual(
            digest.hexadecimal,
            "4b256a64557682b64dbdd1e1685da851552152416d8cc9104ae863fa3c0df5f9"
        )
    }

    func testBundledKeysImportAndCreateSignedEnvelope() throws {
        let keys = try BundleKeyRepository(bundle: .main).loadKeys()
        let crypto = SecureEnvelopeCrypto(
            keys: keys,
            now: { Date(timeIntervalSince1970: 1_789_646_400) },
            makeRequestID: { UUID(uuidString: "12345678-1234-4123-8123-123456789ABC")! }
        )
        let sealed = try crypto.seal(message: "hello")
        let envelope = try JSONDecoder().decode(RequestEnvelope.self, from: sealed.body)

        let encryptedKey = try XCTUnwrap(Data(base64Encoded: envelope.encryptedKey))
        let nonce = try XCTUnwrap(Data(base64Encoded: envelope.nonce))
        let ciphertext = try XCTUnwrap(Data(base64Encoded: envelope.ciphertext))
        let tag = try XCTUnwrap(Data(base64Encoded: envelope.tag))
        let signature = try XCTUnwrap(Data(base64Encoded: envelope.signature))
        let input = try CanonicalSignatureInput.make(
            encryptedKey: encryptedKey,
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )
        let clientPublicKey = try XCTUnwrap(SecKeyCopyPublicKey(keys.clientPrivateKey))
        var verificationError: Unmanaged<CFError>?
        XCTAssertTrue(SecKeyVerifySignature(
            clientPublicKey,
            .rsaSignatureMessagePSSSHA256,
            input as CFData,
            signature as CFData,
            &verificationError
        ))
        XCTAssertNil(verificationError)
        XCTAssertEqual(envelope.version, SecureProtocolConstants.version)
        XCTAssertEqual(nonce.count, SecureProtocolConstants.nonceBytes)
        XCTAssertEqual(tag.count, SecureProtocolConstants.tagBytes)
    }

    func testOpensAuthenticatedResponseAndRejectsWrongRequest() throws {
        let keys = try BundleKeyRepository(bundle: .main).loadKeys()
        let crypto = SecureEnvelopeCrypto(keys: keys)
        let symmetricKey = SymmetricKey(data: Data(repeating: 0x42, count: 32))
        let requestID = "12345678-1234-4123-8123-123456789abc"
        let response = ResponsePlaintext(
            requestID: requestID,
            code: 0,
            receiptID: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
            message: "Message accepted."
        )
        let plaintext = try JSONEncoder().encode(response)
        let sealed = try AES.GCM.seal(
            plaintext,
            using: symmetricKey,
            nonce: AES.GCM.Nonce(data: Data(repeating: 7, count: 12)),
            authenticating: SecureProtocolConstants.responseAuthenticatedData(requestID: requestID)
        )
        let envelope = ResponseEnvelope(
            version: 1,
            nonce: sealed.nonce.withUnsafeBytes { Data($0) }.base64EncodedString(),
            ciphertext: sealed.ciphertext.base64EncodedString(),
            tag: sealed.tag.base64EncodedString()
        )
        let wire = try JSONEncoder().encode(envelope)

        let opened = try crypto.openResponse(
            wire,
            context: ResponseContext(symmetricKey: symmetricKey, requestID: requestID)
        )
        XCTAssertEqual(opened, response)
        XCTAssertThrowsError(try crypto.openResponse(
            wire,
            context: ResponseContext(
                symmetricKey: symmetricKey,
                requestID: "ffffffff-ffff-4fff-8fff-ffffffffffff"
            )
        ))
    }
}

@MainActor
final class ContentViewModelTests: XCTestCase {
    func testDisplaysRawAndDecryptedResponse() async {
        let responseData = Data("{\"encrypted\":true}".utf8)
        let network = RecordingNetworkService(response: responseData)
        let crypto = RecordingCrypto()
        let configuration = LabConfiguration(
            endpoint: URL(string: "https://example.test/secure-communication/request")!
        )
        let viewModel = ContentViewModel(
            configuration: configuration,
            networkService: network,
            crypto: crypto
        )

        viewModel.sendMessage()
        while viewModel.isLoading {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.rawResponse, "{\"encrypted\":true}")
        XCTAssertTrue(viewModel.decryptedResponse?.contains("Receipt: receipt-id") == true)
        let requests = await network.requests
        XCTAssertEqual(requests.first?.url, configuration.endpoint)
        XCTAssertEqual(requests.first?.httpMethod, "POST")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
}

private actor RecordingNetworkService: NetworkServiceProtocol {
    let response: Data
    private(set) var requests: [URLRequest] = []

    init(response: Data) {
        self.response = response
    }

    func process(request: URLRequest) async throws -> Data {
        requests.append(request)
        return response
    }
}

private final class RecordingCrypto: SecureEnvelopeCryptoProtocol, @unchecked Sendable {
    private let context = ResponseContext(
        symmetricKey: SymmetricKey(data: Data(repeating: 0x42, count: 32)),
        requestID: "12345678-1234-4123-8123-123456789abc"
    )

    func seal(message _: String) throws -> SealedRequest {
        SealedRequest(body: Data("{\"request\":true}".utf8), responseContext: context)
    }

    func openResponse(_: Data, context _: ResponseContext) throws -> ResponsePlaintext {
        ResponsePlaintext(
            requestID: context.requestID,
            code: 0,
            receiptID: "receipt-id",
            message: "Message accepted."
        )
    }
}

private extension Data {
    var hexadecimal: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
