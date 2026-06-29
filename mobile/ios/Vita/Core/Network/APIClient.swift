import Foundation

// MARK: — Client HTTP centralisé

actor APIClient {
    static let shared = APIClient()

    // Deux services distincts — l'iOS ne contacte jamais l'ai-engine directement.
    private let authBaseURL: URL  // :3001 — /auth/*
    private let dataBaseURL: URL  // :3002 — tout le reste

    private var accessToken: String?
    private var refreshToken: String?

    private init() {
        let auth = Bundle.main.object(forInfoDictionaryKey: "AUTH_BASE_URL") as? String
            ?? "http://localhost:3001"
        let data = Bundle.main.object(forInfoDictionaryKey: "DATA_BASE_URL") as? String
            ?? "http://localhost:3002"
        authBaseURL = URL(string: auth)!
        dataBaseURL = URL(string: data)!
    }

    // Sélectionne le service cible selon le préfixe du path.
    // /auth/* → auth-service (:3001) ; tout le reste → data-service (:3002).
    private func baseURL(for path: String) -> URL {
        path.hasPrefix("/auth") ? authBaseURL : dataBaseURL
    }

    func setTokens(access: String, refresh: String) {
        accessToken = access
        refreshToken = refresh
        // Persister de manière sécurisée dans le Keychain
        KeychainHelper.save(access, for: "vita.access_token")
        KeychainHelper.save(refresh, for: "vita.refresh_token")
    }

    func clearTokens() {
        accessToken = nil
        refreshToken = nil
        KeychainHelper.delete("vita.access_token")
        KeychainHelper.delete("vita.refresh_token")
    }

    // MARK: — Méthodes publiques

    func get<T: Decodable>(_ path: String, queryParams: [String: String] = [:]) async throws -> T {
        let url = buildURL(path, params: queryParams)
        let request = try buildRequest(url: url, method: "GET")
        return try await perform(request)
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let url = buildURL(path)
        var request = try buildRequest(url: url, method: "POST")
        // Les routes /auth/* attendent du camelCase (contrat Zod du backend).
        // Toutes les autres routes attendent du snake_case (contrat data-service).
        let encoder: JSONEncoder = path.hasPrefix("/auth") ? .vitaAuth : .vita
        let encoded = try encoder.encode(body)
        #if DEBUG
        if let json = String(data: encoded, encoding: .utf8) {
            print("[APIClient] POST \(path) body: \(json)")
        }
        #endif
        request.httpBody = encoded
        return try await perform(request)
    }

    func patch<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let url = buildURL(path)
        var request = try buildRequest(url: url, method: "PATCH")
        request.httpBody = try JSONEncoder.vita.encode(body)
        return try await perform(request)
    }

    func delete(_ path: String) async throws {
        let url = buildURL(path)
        let request = try buildRequest(url: url, method: "DELETE")
        let _: EmptyResponse = try await perform(request)
    }

    // Construit une URLRequest pour une connexion SSE (streaming long-lived).
    // Appelé par VitaSSEClient avant d'ouvrir le flux.
    func sseRequest(path: String) -> URLRequest? {
        guard let token = accessToken else { return nil }
        let url = buildURL(path)
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: — Internals

    private func buildURL(_ path: String, params: [String: String] = [:]) -> URL {
        var components = URLComponents(url: baseURL(for: path).appendingPathComponent(path), resolvingAgainstBaseURL: true)!
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    private func buildRequest(url: URL, method: String) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        #if DEBUG
        if http.statusCode < 200 || http.statusCode >= 300 {
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            print("[APIClient] ⚠️ \(request.httpMethod ?? "?") \(request.url?.path ?? "?") → HTTP \(http.statusCode) | \(body)")
        }
        #endif

        switch http.statusCode {
        case 200...299:
            return try JSONDecoder.vita.decode(T.self, from: data)
        case 401:
            // Tenter un refresh automatique
            if request.url?.path.contains("/auth/refresh") == false {
                try await refreshAccessToken()
                var retried = request
                if let token = accessToken {
                    retried.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                return try await perform(retried)
            }
            throw APIError.unauthorized
        case 409:
            throw APIError.conflict
        case 422:
            throw APIError.validationError(data)
        default:
            throw APIError.serverError(http.statusCode)
        }
    }

    private func refreshAccessToken() async throws {
        guard let refresh = refreshToken else { throw APIError.unauthorized }
        let response: TokenResponse = try await post("/auth/refresh", body: ["refreshToken": refresh])
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        KeychainHelper.save(response.accessToken, for: "vita.access_token")
        KeychainHelper.save(response.refreshToken, for: "vita.refresh_token")
    }
}

// MARK: — Modèles réseau

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

struct EmptyResponse: Codable {}

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case conflict
    case validationError(Data)
    case serverError(Int)
    case noData

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expirée. Reconnecte-toi."
        case .conflict: return "Cette action a déjà été effectuée."
        case .serverError(let code): return "Erreur serveur (\(code))."
        default: return "Une erreur est survenue."
        }
    }
}

// MARK: — Helpers

extension JSONEncoder {
    // Encoder pour data-service : snake_case (ex: duration_minutes, quality_score)
    static let vita: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // Encoder pour auth-service : camelCase strict (contrat Zod : firstName, accessToken…)
    static let vitaAuth: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .useDefaultKeys
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let vita: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: — Keychain
enum KeychainHelper {
    static func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
