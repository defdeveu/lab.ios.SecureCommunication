import Foundation

enum EncryptionConstants {
    static let aesKey = "00112233445566778899aabbccddeeff"
    static let aesData = "00112233445566778899aabbccddeeff|1111111111111111"
    static let iv = "1111111111111111"
}

protocol MessageEncryptionProtocol {
    func encrypt(message: String) throws -> String
}

final class MessageEncryption {
    private let aesKey: String
    private let aesData: String
    private let iv: String
    private let certificateRepository: CertificateRepositoryProtocol
    private let algorithmProvider: AlgorithmProviderProtocol

    init(aesKey: String = EncryptionConstants.aesKey,
         aesData: String = EncryptionConstants.aesData,
         iv: String = EncryptionConstants.iv,
         certificateRepository: CertificateRepositoryProtocol,
         algorithmProvider: AlgorithmProviderProtocol) {
        self.aesKey = aesKey
        self.aesData = aesData
        self.iv = iv
        self.certificateRepository = certificateRepository
        self.algorithmProvider = algorithmProvider
    }
}

extension MessageEncryption: MessageEncryptionProtocol {
    func encrypt(message: String) throws -> String {
        let serverPublicKey = try certificateRepository.certificate(resource: "server-pub-pkcs8", type: "pem")
        let clientPrivateKey = try certificateRepository.certificate(resource: "private-pkcs8", type: "pem")

        let encryptedAESKey = try algorithmProvider.encryptRSA(string: aesData, publicKey: serverPublicKey)
        let encryptedMessage = try algorithmProvider.encryptAES(string: message, publicKey: aesKey, iv: iv)
        let signature = try algorithmProvider.signRSA(data: encryptedMessage, privateKey: clientPrivateKey)

        return ("<request><enckey>\(encryptedAESKey.base64EncodedString())</enckey>" +
                "<message>\(encryptedMessage.base64EncodedString())</message>" +
                "<signature>\(signature.base64EncodedString())</signature></request>")
    }
}
