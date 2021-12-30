import Foundation

// MARK: - Application Services

final class AppRepository {
    static var shared = AppRepository()
    private init() { }

    lazy var networkService: NetworkServiceProtocol = {
        NetworkService()
    }()

    lazy var messageRequest: MessageRequestProtocol = {
        MessageRequest(endpoint: "https://zs.labs.defdev.eu:9998/request")
    }()

    private lazy var algorithmProvider: AlgorithmProviderProtocol = {
        AlgorithmProvider()
    }()

    private lazy var certificateRepository: CertificateRepositoryProtocol = {
        CertificateRepository()
    }()

    lazy var messageEncryption: MessageEncryptionProtocol = {
        MessageEncryption(certificateRepository: certificateRepository,
                          algorithmProvider: algorithmProvider)
    }()
}
