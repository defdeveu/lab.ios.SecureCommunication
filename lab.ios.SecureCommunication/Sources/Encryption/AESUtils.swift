import Foundation
import CommonCrypto

enum AESUtils {
    static func encrypt(string: String, key: String, iv: String) -> Data? {
        return crypt(data: string.data(using: .utf8), key: key, iv: iv, option: CCOperation(kCCEncrypt))
    }

    static func decrypt(data: Data?, key: String, iv: String) -> String? {
        guard let decryptedData = crypt(data: data, key: key, iv: iv, option: CCOperation(kCCDecrypt)) else { return nil }
        return String(bytes: decryptedData, encoding: .utf8)
    }

    private static func crypt(data: Data?, key: String, iv: String, option: CCOperation) -> Data? {
        guard let data = data,
              key.count == kCCKeySizeAES128 || key.count == kCCKeySizeAES256, let keyData = key.data(using: .utf8),
              iv.count == kCCBlockSizeAES128, let ivData = iv.data(using: .utf8)
        else { return nil }

        let cryptLength = data.count + kCCBlockSizeAES128
        var cryptData   = Data(count: cryptLength)

        let keyLength = keyData.count
        let options   = CCOptions(kCCOptionPKCS7Padding)

        var bytesLength = Int(0)

        let status = cryptData.withUnsafeMutableBytes { cryptBytes in
            data.withUnsafeBytes { dataBytes in
                ivData.withUnsafeBytes { ivBytes in
                    keyData.withUnsafeBytes { keyBytes in
                        CCCrypt(option, CCAlgorithm(kCCAlgorithmAES), options, keyBytes.baseAddress, keyLength, ivBytes.baseAddress, dataBytes.baseAddress, data.count, cryptBytes.baseAddress, cryptLength, &bytesLength)
                    }
                }
            }
        }

        guard UInt32(status) == UInt32(kCCSuccess) else {
            debugPrint("Error: Failed to crypt data. Status \(status)")
            return nil
        }

        cryptData.removeSubrange(bytesLength..<cryptData.count)
        return cryptData
    }
}
