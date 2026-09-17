import Foundation

protocol NetworkServiceProtocol: Sendable {
    func process(request: URLRequest) async throws -> Data
}

enum NetworkServiceError: LocalizedError, Equatable {
    case nonHTTPResponse
    case unexpectedStatus(Int)
    case unexpectedContentType(String?)

    var errorDescription: String? {
        switch self {
        case .nonHTTPResponse:
            "The server did not return an HTTP response."
        case let .unexpectedStatus(status):
            "The server returned HTTP status \(status)."
        case let .unexpectedContentType(contentType):
            "The server returned an unexpected content type: \(contentType ?? "missing")."
        }
    }
}

final class NetworkService: NetworkServiceProtocol, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func process(request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkServiceError.nonHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkServiceError.unexpectedStatus(httpResponse.statusCode)
        }
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")
        guard contentType?.lowercased().hasPrefix("application/json") == true else {
            throw NetworkServiceError.unexpectedContentType(contentType)
        }
        return data
    }
}
