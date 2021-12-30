import Foundation

enum AlgorithmProviderError: Error, LocalizedError {
    case rsaEncription
    case aesEncryption
    case signature

    var errorDescription: String? {
        switch self {
        case .rsaEncription:
            return "Cannot complete RSA encryption"
        case .aesEncryption:
            return "Cannot complete AES encryption"
        case .signature:
            return "Cannot private signature"
        }
    }
}

protocol AlgorithmProviderProtocol {
    func encryptRSA(string: String, publicKey: String) throws -> Data
    func encryptAES(string: String, publicKey: String, iv: String) throws -> Data
    func signRSA(data: Data, privateKey: String) throws -> Data
}

final class AlgorithmProvider: AlgorithmProviderProtocol {
    func encryptRSA(string: String, publicKey: String) throws -> Data {
        guard let data = string.data(using: .utf8),
            let result = RSAUtils.encryptData(data, publicKey: publicKey)
        else {
            throw AlgorithmProviderError.rsaEncription
        }

        return result
    }

    func encryptAES(string: String, publicKey: String, iv: String) throws -> Data {
        guard let result = AESUtils.encrypt(string: string, key: publicKey, iv: iv) else {
            throw AlgorithmProviderError.aesEncryption
        }

        return result
    }

    func signRSA(data: Data, privateKey: String) throws -> Data {
        let sha1Data = data.sha1()
        guard let result = RSAUtils.encryptData(sha1Data, privateKey: privateKey)
        else {
            throw AlgorithmProviderError.signature
        }

        return result
    }
}
