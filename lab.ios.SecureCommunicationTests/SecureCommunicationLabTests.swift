import CryptoKit
import Foundation
import Security
import Testing
@testable import lab_ios_SecureCommunication

@Suite
struct LabConfigurationTests {
    @Test
    func parsesHostedEndpoint() throws {
        let configuration = try LabConfiguration.parse([
            "LabSecureCommunicationURL": "https://zsk.labs.def.dev/secure-communication/request",
        ])
        #expect(configuration.endpoint.scheme == "https")
        #expect(configuration.endpoint.host() == "zsk.labs.def.dev")
        #expect(configuration.endpoint.path() == "/secure-communication/request")
    }

    @Test
    func rejectsHTTPAndWrongPath() {
        #expect(throws: (any Error).self) {
            try LabConfiguration.parse([
                "LabSecureCommunicationURL": "http://zsk.labs.def.dev/secure-communication/request",
            ])
        }
        #expect(throws: (any Error).self) {
            try LabConfiguration.parse([
                "LabSecureCommunicationURL": "https://zsk.labs.def.dev/request",
            ])
        }
    }
}

@Suite
struct SecureEnvelopeTests {
    @Test
    func canonicalSignatureInputMatchesGoVector() throws {
        let input = try CanonicalSignatureInput.make(
            encryptedKey: Data([1, 2]),
            nonce: Data([3]),
            ciphertext: Data([4, 5, 6]),
            tag: Data([7])
        )
        let digest = Data(SHA256.hash(data: input))
        #expect(digest.hexadecimal == "4b256a64557682b64dbdd1e1685da851552152416d8cc9104ae863fa3c0df5f9")
    }

    @Test
    func bundledKeysImportAndCreateSignedEnvelope() throws {
        let keys = try BundleKeyRepository(bundle: .main).loadKeys()
        let crypto = SecureEnvelopeCrypto(
            keys: keys,
            now: { Date(timeIntervalSince1970: 1_789_646_400) },
            makeRequestID: { UUID(uuidString: "12345678-1234-4123-8123-123456789ABC")! }
        )
        let sealed = try crypto.seal(message: "hello")
        let envelope = try JSONDecoder().decode(RequestEnvelope.self, from: sealed.body)

        let encryptedKey = try #require(Data(base64Encoded: envelope.encryptedKey))
        let nonce = try #require(Data(base64Encoded: envelope.nonce))
        let ciphertext = try #require(Data(base64Encoded: envelope.ciphertext))
        let tag = try #require(Data(base64Encoded: envelope.tag))
        let signature = try #require(Data(base64Encoded: envelope.signature))
        let input = try CanonicalSignatureInput.make(
            encryptedKey: encryptedKey,
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )
        let clientPublicKey = try #require(SecKeyCopyPublicKey(keys.clientPrivateKey))
        var verificationError: Unmanaged<CFError>?
        #expect(SecKeyVerifySignature(
            clientPublicKey,
            .rsaSignatureMessagePSSSHA256,
            input as CFData,
            signature as CFData,
            &verificationError
        ))
        #expect(verificationError == nil)
        #expect(envelope.version == SecureProtocolConstants.version)
        #expect(nonce.count == SecureProtocolConstants.nonceBytes)
        #expect(tag.count == SecureProtocolConstants.tagBytes)
    }

    @Test
    func opensAuthenticatedResponseAndRejectsWrongRequest() throws {
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
        #expect(opened == response)
        #expect(throws: (any Error).self) {
            try crypto.openResponse(
                wire,
                context: ResponseContext(
                    symmetricKey: symmetricKey,
                    requestID: "ffffffff-ffff-4fff-8fff-ffffffffffff"
                )
            )
        }
    }
}

@MainActor
@Suite
struct ContentViewModelTests {
    @Test
    func displaysRawAndDecryptedResponse() async {
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

        #expect(viewModel.rawResponse == "{\"encrypted\":true}")
        #expect(viewModel.decryptedResponse?.contains("Receipt: receipt-id") == true)
        let requests = await network.requests
        #expect(requests.first?.url == configuration.endpoint)
        #expect(requests.first?.httpMethod == "POST")
        #expect(requests.first?.value(forHTTPHeaderField: "Content-Type") == "application/json")
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