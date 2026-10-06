import Foundation

enum APIError: LocalizedError {
    case badURL
    case unauthorized
    case rateLimited
    case badNumber(String)
    case server(Int)
    case transport(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "The server address in Settings isn't a valid URL."
        case .unauthorized:
            return "The server rejected this client key. Check Settings."
        case .rateLimited:
            return "Too many lookups this minute. Try again shortly."
        case .badNumber(let detail):
            return detail.isEmpty ? "That doesn't look like a phone number." : detail
        case .server(let code):
            return "The lookup server returned an error (\(code))."
        case .transport(let message):
            return "Couldn't reach the lookup server: \(message)"
        case .decoding:
            return "The server sent a response DeskCall couldn't read."
        }
    }
}

/// Thin client for the DeskCall FastAPI backend.
///
/// Nothing identifying is attached to a request: no device token, no contact
/// data, no analytics header. The only payload is the number being looked up.
struct DeskCallAPI {
    let baseURL: URL
    let clientKey: String?
    let session: URLSession

    init(baseURL: URL = AppConfig.baseURL,
         clientKey: String? = AppConfig.clientKey,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.clientKey = clientKey
        self.session = session
    }

    private func request(_ path: String, method: String, body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 10
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let clientKey, !clientKey.isEmpty {
            req.setValue(clientKey, forHTTPHeaderField: "X-DeskCall-Key")
        }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.decoding }

        switch http.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.decoding
            }
        case 401:
            throw APIError.unauthorized
        case 422, 400:
            throw APIError.badNumber(Self.detail(from: data))
        case 429:
            throw APIError.rateLimited
        default:
            throw APIError.server(http.statusCode)
        }
    }

    private static func detail(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        if let detail = object["detail"] as? String { return detail }
        if let list = object["detail"] as? [[String: Any]],
           let first = list.first, let message = first["msg"] as? String {
            // FastAPI validation errors arrive as a list; surface the first one.
            return message.replacingOccurrences(of: "Value error, ", with: "")
        }
        return ""
    }

    func lookup(number: String) async throws -> CallerProfile {
        let body = try JSONEncoder().encode(["phone_number": number])
        return try await send(request("api/v1/lookup", method: "POST", body: body),
                              as: CallerProfile.self)
    }

    func reportSpam(number: String) async throws {
        let body = try JSONEncoder().encode(["phone_number": number, "category": "spam"])
        struct Ack: Decodable { let reports: Int }
        _ = try await send(request("api/v1/report", method: "POST", body: body), as: Ack.self)
    }

    func fetchDirectory() async throws -> RemoteDirectory {
        try await send(request("api/v1/directory", method: "GET"), as: RemoteDirectory.self)
    }

    func health() async throws -> [String: String] {
        struct Health: Decodable { let status: String; let mode: String }
        let result = try await send(request("health", method: "GET"), as: Health.self)
        return ["status": result.status, "mode": result.mode]
    }
}
