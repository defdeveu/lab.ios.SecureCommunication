import Foundation
import Security

struct ApplicationKeys: @unchecked Sendable {
    let serverPublicKey: SecKey
    let clientPrivateKey: SecKey
}

protocol KeyRepositoryProtocol: Sendable {
    func loadKeys() throws -> ApplicationKeys
}

// Apple documents SecKey's external RSA representation as PKCS#1. Shipping that
// exact DER form removes the hand-written ASN.1 header stripping that the old
// Objective-C helper needed for PEM/PKCS#8 input.
final class BundleKeyRepository: KeyRepositoryProtocol, @unchecked Sendable {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadKeys() throws -> ApplicationKeys {
        ApplicationKeys(
            serverPublicKey: try loadRSAKey(
                resource: "server-public.pkcs1",
                extension: "der",
                keyClass: kSecAttrKeyClassPublic,
                displayName: "server public"
            ),
            clientPrivateKey: try loadRSAKey(
                resource: "client-private.pkcs1",
                extension: "der",
                keyClass: kSecAttrKeyClassPrivate,
                displayName: "teaching client private"
            )
        )
    }

    private func loadRSAKey(
        resource: String,
        extension fileExtension: String,
        keyClass: CFString,
        displayName: String
    ) throws -> SecKey {
        guard let url = bundle.url(forResource: resource, withExtension: fileExtension),
              let data = try? Data(contentsOf: url)
        else {
            throw SecureProtocolError.invalidKey(displayName)
        }

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: keyClass,
            kSecAttrKeySizeInBits: 3072,
        ]
        var importError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &importError) else {
            _ = importError?.takeRetainedValue()
            throw SecureProtocolError.invalidKey(displayName)
        }

        // Do not trust only the attributes supplied to SecKeyCreateWithData;
        // read back the imported object and verify the actual algorithm/size.
        // Security.framework returns an NSDictionary-style object. Bridge its
        // Core Foundation string keys to Swift String once, then compare plain
        // Swift values. Swift 6 deliberately diagnoses `Any as? CFString`
        // because that Core Foundation bridge is unconditional; spelling the
        // boundary this way keeps the validation both explicit and warning-free.
        guard let imported = SecKeyCopyAttributes(key) as? [String: Any],
              imported[kSecAttrKeyType as String] as? String == kSecAttrKeyTypeRSA as String,
              (imported[kSecAttrKeySizeInBits as String] as? NSNumber)?.intValue == 3072
        else {
            throw SecureProtocolError.invalidKey(displayName)
        }
        return key
    }
}
