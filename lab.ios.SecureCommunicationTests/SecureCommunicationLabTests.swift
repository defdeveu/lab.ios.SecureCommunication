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
struct MessageEncryptionTests {
    @Test
    func bundledKeysLoadFromTheAppBundle() throws {
        let keys = try BundleKeyRepository(bundle: .main).loadKeys()
        #expect(SecKeyGetBlockSize(keys.serverPublicKey) == 256)
        #expect(SecKeyGetBlockSize(keys.clientPrivateKey) == 256)
    }

    @Test
    func encryptBuildsTheWireRequest() throws {
        let keys = try BundleKeyRepository(bundle: .main).loadKeys()
        let sealed = try MessageEncryption(keys: keys).encrypt(message: "hello")
        let xml = try #require(String(data: sealed.body, encoding: .utf8))
        let fields = try wireFields(fromRequest: xml)

        let ciphertext = try #require(Data(base64Encoded: fields.message))
        #expect(ciphertext.count == 16)
        let plaintext = try MessageCrypto.aesCBCDecrypt(
            ciphertext,
            key: sealed.material.key,
            iv: sealed.material.iv
        )
        #expect(String(decoding: plaintext, as: UTF8.self) == "hello")

        let wrappedKey = try #require(Data(base64Encoded: fields.enckey))
        #expect(wrappedKey.count == 256)

        let signature = try #require(Data(base64Encoded: fields.signature))
        let publicKey = try #require(SecKeyCopyPublicKey(keys.clientPrivateKey))
        var verificationError: Unmanaged<CFError>?
        #expect(SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePKCS1v15SHA1,
            ciphertext as CFData,
            signature as CFData,
            &verificationError
        ))
        #expect(verificationError == nil)

        #expect(MessageEncryptionConstants.aesKey == "00112233445566778899aabbccddeeff")
        #expect(MessageEncryptionConstants.aesIV == "1111111111111111")
    }

    @Test
    func decryptsTheServerResponse() throws {
        let keys = try BundleKeyRepository(bundle: .main).loadKeys()
        let encryption = MessageEncryption(keys: keys)
        let acknowledgment = "<code>0</code><id>0123456789abcdef0123456789abcdef</id>"
        let ciphertext = try MessageCrypto.aesCBCEncrypt(
            Data(acknowledgment.utf8),
            key: SymmetricMaterial.classroom.key,
            iv: SymmetricMaterial.classroom.iv
        )
        let wire = Data("<response>\(ciphertext.base64EncodedString())</response>".utf8)

        let decrypted = try encryption.decryptResponse(wire, material: .classroom)
        #expect(decrypted == acknowledgment)
        #expect(throws: (any Error).self) {
            try encryption.decryptResponse(Data("not a response".utf8), material: .classroom)
        }
    }
}

@MainActor
@Suite
struct ContentViewModelTests {
    @Test
    func displaysRawAndDecryptedResponse() async throws {
        let keys = try BundleKeyRepository(bundle: .main).loadKeys()
        let acknowledgment = "<code>0</code><id>0123456789abcdef0123456789abcdef</id>"
        let ciphertext = try MessageCrypto.aesCBCEncrypt(
            Data(acknowledgment.utf8),
            key: SymmetricMaterial.classroom.key,
            iv: SymmetricMaterial.classroom.iv
        )
        let wire = Data("<response>\(ciphertext.base64EncodedString())</response>".utf8)
        let network = RecordingNetworkService(response: wire)
        let configuration = LabConfiguration(
            endpoint: URL(string: "https://example.test/secure-communication/request")!
        )
        let viewModel = ContentViewModel(
            configuration: configuration,
            networkService: network,
            encryption: MessageEncryption(keys: keys)
        )

        viewModel.sendMessage()
        while viewModel.isLoading {
            await Task.yield()
        }

        #expect(viewModel.rawResponse == String(decoding: wire, as: UTF8.self))
        #expect(viewModel.decryptedResponse == acknowledgment)
        #expect(viewModel.status == "Response received")
        let requests = await network.requests
        #expect(requests.first?.url == configuration.endpoint)
        #expect(requests.first?.httpMethod == "POST")
        #expect(requests.first?.value(forHTTPHeaderField: "Content-Type") == "application/text")
    }

    @Test
    func reportsTransportFailures() async throws {
        let keys = try BundleKeyRepository(bundle: .main).loadKeys()
        let configuration = LabConfiguration(
            endpoint: URL(string: "https://example.test/secure-communication/request")!
        )
        let viewModel = ContentViewModel(
            configuration: configuration,
            networkService: FailingNetworkService(),
            encryption: MessageEncryption(keys: keys)
        )

        viewModel.sendMessage()
        while viewModel.isLoading {
            await Task.yield()
        }

        #expect(viewModel.status == "The server returned HTTP status 400.")
        #expect(viewModel.rawResponse == nil)
        #expect(viewModel.decryptedResponse == nil)
    }
}

private func wireFields(fromRequest xml: String) throws -> (enckey: String, message: String, signature: String) {
    func value(of tag: String) throws -> String {
        let opening = try #require(xml.range(of: "<\(tag)>"))
        let closing = try #require(xml.range(of: "</\(tag)>"))
        return String(xml[opening.upperBound..<closing.lowerBound])
    }
    return (try value(of: "enckey"), try value(of: "message"), try value(of: "signature"))
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

private actor FailingNetworkService: NetworkServiceProtocol {
    func process(request _: URLRequest) async throws -> Data {
        throw NetworkServiceError.unexpectedStatus(400)
    }
}
