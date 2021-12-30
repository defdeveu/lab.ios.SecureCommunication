import Foundation
import Combine
import UIKit

class ContentViewModel: ObservableObject {
    @Published var response: Response = .none
    @Published var message: String = "Demo message"

    private var subscriptions = Set<AnyCancellable>()
    private let networkService: NetworkServiceProtocol
    private let messageRequest: MessageRequestProtocol
    private let messageEncryption: MessageEncryptionProtocol

    init(networkService: NetworkServiceProtocol = AppRepository.shared.networkService,
         messageRequest: MessageRequestProtocol = AppRepository.shared.messageRequest,
         messageEncryption: MessageEncryptionProtocol = AppRepository.shared.messageEncryption) {
        self.networkService = networkService
        self.messageRequest = messageRequest
        self.messageEncryption = messageEncryption
    }

    func sendMessage() {
        let encryptedMessage: String
        let request: URLRequest

        do {
            encryptedMessage = try messageEncryption.encrypt(message: message)
            request = try messageRequest.request(with: encryptedMessage)
        } catch {
            response = .error(error.localizedDescription)
            return
        }

        response = .progress

        networkService.process(request: request)
            .sink { [weak self] result in
                switch result {
                case .failure(let error):
                    self?.response = .error(error.localizedDescription)
                case .finished:
                    break
                }
            } receiveValue: { [weak self] data in
                self?.response = .output(String(data: data, encoding: .utf8) ?? "<empty>")
            }
            .store(in: &subscriptions)
    }
}

// MARK: - Response

extension ContentViewModel {
    enum Response {
        case none
        case progress
        case output(String)
        case error(String?)

        var description: String {
            switch self {
            case .none:
                return "No response"
            case .progress:
                return "In progress..."
            case .output(let data):
                return "Recieved:\n\n\(data)"
            case .error(let error):
                return "Error has occured:\n\n\(error ?? "Unable to read response")"
            }
        }

        var isInProgress: Bool {
            switch self {
            case .progress:
                return true
            default:
                return false
            }
        }
    }
}
