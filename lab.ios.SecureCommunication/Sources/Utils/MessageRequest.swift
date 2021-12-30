import Foundation

protocol MessageRequestProtocol {
    func request(with message: String) throws -> URLRequest
}

final class MessageRequest {
    private let endpoint: String

    init(endpoint: String) {
        self.endpoint = endpoint
    }
}

extension MessageRequest: MessageRequestProtocol {
    func request(with message: String) throws -> URLRequest {
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.addValue("application/text", forHTTPHeaderField: "Content-type")
        request.httpBody = message.data(using: .utf8)
        request.httpMethod = "POST"

        return request
    }
}
