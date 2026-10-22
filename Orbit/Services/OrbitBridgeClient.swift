//
//  OrbitBridgeClient.swift
//  Orbit
//
//  HTTP bridge client for Deck
//

import Foundation

enum OrbitBridgeError: LocalizedError {
    case unauthorized
    case invalidResponse
    case missingResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Deck rejected the Orbit request"
        case .invalidResponse:
            return "Invalid response from Deck"
        case .missingResponse:
            return "Deck returned empty response"
        case .httpError(let code, let message):
            return "Deck error (HTTP \(code)): \(message)"
        }
    }
}

final class OrbitBridgeClient {
    static let shared = OrbitBridgeClient()

    private static let port = 53129
    private static let baseURL = URL(string: "http://127.0.0.1:\(port)")!
    private static let tokenFileName = "orbit_bridge_token"
    private static let tokenDirectoryName = "Deck"
    private static var sharedToken: String = {
        loadTokenFromDisk() ?? ""
    }()

    private static func reloadToken() {
        sharedToken = loadTokenFromDisk() ?? ""
    }

    private let session: URLSession
    private let encoder = JSONEncoder()

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 4
        session = URLSession(configuration: config)
    }

    // MARK: - Token Loading

    private static var tokenFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent(tokenDirectoryName, isDirectory: true)
            .appendingPathComponent(tokenFileName, isDirectory: false)
    }

    private static func loadTokenFromDisk() -> String? {
        do {
            let url = tokenFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    func health(completion: @escaping @MainActor @Sendable (Result<String, Error>) -> Void) {
        request(method: "GET", path: "/orbit/health", query: nil, body: nil) { result in
            switch result {
            case .success(let data):
                let reply = String(data: data, encoding: .utf8) ?? ""
                completion(.success(reply))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func fetchRecentItems(limit: Int, completion: @escaping @MainActor @Sendable (Result<Data, Error>) -> Void) {
        request(method: "GET", path: "/orbit/recent", query: ["limit": "\(limit)"], body: nil, completion: completion)
    }

    func fetchItemPayload(_ uniqueId: String, completion: @escaping @MainActor @Sendable (Result<Data, Error>) -> Void) {
        request(method: "GET", path: "/orbit/item", query: ["uniqueId": uniqueId], body: nil, completion: completion)
    }

    func deleteItems(_ uniqueIds: [String], completion: @escaping @MainActor @Sendable (Result<Bool, Error>) -> Void) {
        do {
            let payload = OrbitDeleteRequest(uniqueIds: uniqueIds)
            let body = try encoder.encode(payload)
            request(method: "POST", path: "/orbit/delete", query: nil, body: body) { result in
                switch result {
                case .success:
                    completion(.success(true))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    func copyItem(_ uniqueId: String, completion: @escaping @MainActor @Sendable (Result<Bool, Error>) -> Void) {
        do {
            let payload = OrbitCopyRequest(uniqueId: uniqueId)
            let body = try encoder.encode(payload)
            request(method: "POST", path: "/orbit/copy", query: nil, body: body) { result in
                switch result {
                case .success:
                    completion(.success(true))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    private func request(
        method: String,
        path: String,
        query: [String: String]?,
        body: Data?,
        allowRetry: Bool = true,
        completion: @escaping @MainActor @Sendable (Result<Data, Error>) -> Void
    ) {
        guard let url = makeURL(path: path, query: query) else {
            completion(.failure(OrbitBridgeError.invalidResponse))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Self.sharedToken, forHTTPHeaderField: "X-Orbit-Token")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                Task { @MainActor in
                    completion(.failure(error))
                }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                Task { @MainActor in
                    completion(.failure(OrbitBridgeError.invalidResponse))
                }
                return
            }
            let responseData = data ?? Data()
            if http.statusCode == 401 {
                if allowRetry {
                    Task { @MainActor in
                        Self.reloadToken()
                        self.request(
                            method: method,
                            path: path,
                            query: query,
                            body: body,
                            allowRetry: false,
                            completion: completion
                        )
                    }
                    return
                }
                Task { @MainActor in
                    completion(.failure(OrbitBridgeError.unauthorized))
                }
                return
            }
            guard (200...299).contains(http.statusCode) else {
                let message = String(data: responseData, encoding: .utf8) ?? ""
                Task { @MainActor in
                    completion(.failure(OrbitBridgeError.httpError(http.statusCode, message)))
                }
                return
            }
            if responseData.isEmpty {
                Task { @MainActor in
                    completion(.failure(OrbitBridgeError.missingResponse))
                }
                return
            }
            Task { @MainActor in
                completion(.success(responseData))
            }
        }
        task.resume()
    }

    private func makeURL(path: String, query: [String: String]?) -> URL? {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        if let query {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components?.url
    }
}

private struct OrbitDeleteRequest: Codable {
    let uniqueIds: [String]
}

private struct OrbitCopyRequest: Codable {
    let uniqueId: String
}
