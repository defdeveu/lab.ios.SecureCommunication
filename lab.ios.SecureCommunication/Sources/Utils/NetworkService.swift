import Foundation
import Combine

/// A service protocol for executing network requests
protocol NetworkServiceProtocol {
    func process(request: URLRequest) -> AnyPublisher<Data, Error>
}

/// Network service for actual network communication
final class NetworkService {
    private let session: URLSession
    init(session: URLSession = URLSession.shared) {
        self.session = session
    }
}

// MARK: - NetworkServiceProtocol

extension NetworkService: NetworkServiceProtocol {
    func process(request: URLRequest) -> AnyPublisher<Data, Error> {
        session.dataTaskPublisher(for: request)
            .tryMap { output in
                guard let httpResponse = output.response as? HTTPURLResponse,
                    httpResponse.statusCode == 200
                else { throw URLError(.badServerResponse) }

                return output.data
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
