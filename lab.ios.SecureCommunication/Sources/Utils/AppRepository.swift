import Foundation

struct LabConfiguration: Equatable, Sendable {
    let endpoint: URL

    static func load(from bundle: Bundle = .main) throws -> LabConfiguration {
        try parse(bundle.infoDictionary ?? [:])
    }

    static func parse(_ values: [String: Any]) throws -> LabConfiguration {
        guard let value = values["LabSecureCommunicationURL"] as? String,
              let endpoint = URL(string: value),
              endpoint.scheme == "https",
              endpoint.host() != nil,
              endpoint.path() == "/secure-communication/request"
        else {
            throw LabConfigurationError.invalidEndpoint
        }
        return LabConfiguration(endpoint: endpoint)
    }

    static let fallback = LabConfiguration(
        endpoint: URL(string: "https://zsk.labs.def.dev/secure-communication/request")!
    )
}

enum LabConfigurationError: LocalizedError, Equatable {
    case invalidEndpoint

    var errorDescription: String? {
        "LabSecureCommunicationURL must be an HTTPS /secure-communication/request URL."
    }
}

enum AppRepository {
    @MainActor
    static func makeViewModel(bundle: Bundle = .main) -> ContentViewModel {
        do {
            let configuration = try LabConfiguration.load(from: bundle)
            let keys = try BundleKeyRepository(bundle: bundle).loadKeys()
            return ContentViewModel(
                configuration: configuration,
                networkService: NetworkService(),
                crypto: SecureEnvelopeCrypto(keys: keys)
            )
        } catch {
            let message = "Configuration error: \(error.localizedDescription)"
            return ContentViewModel(
                configuration: .fallback,
                networkService: NetworkService(),
                crypto: UnavailableEnvelopeCrypto(message: message),
                initialMessage: message
            )
        }
    }
}
