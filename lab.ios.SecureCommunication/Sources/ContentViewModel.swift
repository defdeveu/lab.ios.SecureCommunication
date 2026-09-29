import Foundation
import Observation

@MainActor
@Observable
final class ContentViewModel {
    var message = "Demo message"
    private(set) var status = "Ready"
    private(set) var rawResponse: String?
    private(set) var decryptedResponse: String?
    private(set) var isLoading = false

    @ObservationIgnored private let configuration: LabConfiguration
    @ObservationIgnored private let networkService: any NetworkServiceProtocol
    @ObservationIgnored private let encryption: any MessageEncryptionProtocol
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var activeOperation: UUID?

    init(
        configuration: LabConfiguration,
        networkService: any NetworkServiceProtocol,
        encryption: any MessageEncryptionProtocol,
        initialMessage: String? = nil
    ) {
        self.configuration = configuration
        self.networkService = networkService
        self.encryption = encryption
        if let initialMessage {
            status = initialMessage
        }
    }

    func sendMessage() {
        cancelRequest(updateStatus: false)
        rawResponse = nil
        decryptedResponse = nil

        let sealed: SealedMessage
        do {
            sealed = try encryption.encrypt(message: message)
        } catch {
            status = error.localizedDescription
            return
        }

        var request = URLRequest(
            url: configuration.endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.httpMethod = "POST"
        request.httpBody = sealed.body
        request.setValue("application/text", forHTTPHeaderField: "Content-Type")

        let operation = UUID()
        activeOperation = operation
        isLoading = true
        status = "Encrypting and sending…"
        let networkService = self.networkService
        let encryption = self.encryption

        requestTask = Task { [weak self] in
            do {
                let data = try await networkService.process(request: request)
                try Task.checkCancellation()
                let raw = String(decoding: data, as: UTF8.self)
                let decrypted = try encryption.decryptResponse(data, material: sealed.material)
                try Task.checkCancellation()
                guard self?.activeOperation == operation else { return }
                self?.rawResponse = raw
                self?.decryptedResponse = decrypted
                self?.status = "Response received"
            } catch is CancellationError {
                return
            } catch {
                guard self?.activeOperation == operation else { return }
                self?.status = error.localizedDescription
            }
            guard self?.activeOperation == operation else { return }
            self?.isLoading = false
            self?.requestTask = nil
            self?.activeOperation = nil
        }
    }

    func cancelRequest() {
        cancelRequest(updateStatus: true)
    }

    private func cancelRequest(updateStatus: Bool) {
        requestTask?.cancel()
        requestTask = nil
        activeOperation = nil
        isLoading = false
        if updateStatus {
            status = "Request cancelled"
        }
    }
}
