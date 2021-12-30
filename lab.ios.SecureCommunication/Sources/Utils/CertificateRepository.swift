import Foundation

protocol CertificateRepositoryProtocol {
    func certificate(resource: String?, type: String?) throws -> String
}

final class CertificateRepository: CertificateRepositoryProtocol {
    func certificate(resource: String?, type: String?) throws -> String {
        guard let path = Bundle.main.path(forResource: resource, ofType: type) else {
            throw CocoaError(.fileNoSuchFile)
        }

        return try String(contentsOfFile: path, encoding: .utf8)
    }
}
