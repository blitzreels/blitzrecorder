import AppKit
import AuthenticationServices
import CryptoKit
import Observation
import Security

struct BlitzReelsHTTPRequest {
    let path: String
    let method: String
    let key: String?
    let body: [String: Any]?
    var idempotencyKey: String? = nil
}

struct BlitzReelsHTTPClient {
    let origin: URL
    let session: URLSession

    static var configured: BlitzReelsHTTPClient {
        #if DEBUG
        if let value = UserDefaults.standard.string(forKey: "BlitzReelsOrigin"),
           let url = URL(string: value),
           ["localhost", "127.0.0.1", "::1"].contains(url.host ?? ""),
           ["http", "https"].contains(url.scheme ?? "") {
            return .init(origin: url, session: .shared)
        }
        #endif
        return .init(origin: URL(string: "https://blitzreels.com")!, session: .shared)
    }

    func send<Response: Decodable>(_ request: BlitzReelsHTTPRequest) async throws -> Response {
        guard let url = URL(string: request.path, relativeTo: origin.appendingPathComponent("/")),
              url.host == origin.host else { throw BlitzReelsHandoffError.invalidResponse }
        var http = URLRequest(url: url)
        http.httpMethod = request.method
        http.timeoutInterval = 60
        http.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = request.key { http.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let id = request.idempotencyKey { http.setValue(id, forHTTPHeaderField: "Idempotency-Key") }
        if let body = request.body {
            http.setValue("application/json", forHTTPHeaderField: "Content-Type")
            http.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: http)
        try Self.validate(.init(data: data, response: response))
        return try JSONDecoder().decode(Response.self, from: data)
    }

    struct ResponseValidation { let data: Data; let response: URLResponse }

    static func validate(_ request: ResponseValidation) throws {
        guard let response = request.response as? HTTPURLResponse else { throw BlitzReelsHandoffError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 { throw BlitzReelsHandoffError.signInAgain }
            if response.statusCode == 404 { throw BlitzReelsHandoffError.missingAsset }
            let object = (try? JSONSerialization.jsonObject(with: request.data)) as? [String: Any]
            let error = object?["error"] as? [String: Any]
            let message = error?["message"] as? String ?? object?["error_description"] as? String
            if object?["error"] as? String == "invalid_grant" {
                throw BlitzReelsHandoffError.signInAgain
            }
            if response.statusCode == 402 {
                throw BlitzReelsHandoffError.planAccess(message ?? "Your workspace has reached its plan limit.")
            }
            if response.statusCode == 403 {
                if error?["onboarding_url"] is String {
                    throw BlitzReelsHandoffError.accountSetup(message ?? "Finish setting up your BlitzReels account.")
                }
                if let message { throw BlitzReelsHandoffError.server(message) }
                throw BlitzReelsHandoffError.workspaceAccess
            }
            if response.statusCode == 429 { throw BlitzReelsHandoffError.rateLimited }
            throw BlitzReelsHandoffError.server(message ?? "BlitzReels could not finish the request (\(response.statusCode)). Try again.")
        }
    }

    struct CreateURLRequest { let assetID: String; let organizationID: String }

    func createURL(_ request: CreateURLRequest) -> URL {
        var parts = URLComponents(url: origin.appendingPathComponent("dashboard/create"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            .init(name: "mode", value: "video"), .init(name: "source", value: "blitzrecorder"),
            .init(name: "asset", value: request.assetID), .init(name: "org", value: request.organizationID)
        ]
        return parts.url!
    }
}

struct BlitzReelsCredential: Codable {
    let clientID: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

struct BlitzReelsCredentialStore {
    let origin: URL

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "dev.blitzreels.blitzrecorder",
            kSecAttrAccount as String: "blitzreels-oauth:\(origin.absoluteString)"
        ]
    }

    func load() -> BlitzReelsCredential? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(BlitzReelsCredential.self, from: data)
    }

    func save(_ credential: BlitzReelsCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw BlitzReelsHandoffError.keychain }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw BlitzReelsHandoffError.keychain }
    }

    func clear() { SecItemDelete(query as CFDictionary) }
}

struct BlitzReelsWorkspace: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct BlitzReelsAccount: Decodable {
    struct User: Decodable {
        let id: String
        let email: String
        let display_name: String?
    }
    let user: User
    let workspaces: [BlitzReelsWorkspace]
    let default_workspace_id: String
}

struct BlitzReelsOAuthProof {
    let verifier: String
    let state: String

    static func make() throws -> Self {
        func randomValue() throws -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw BlitzReelsHandoffError.authorization
            }
            return encode(Data(bytes))
        }
        return try .init(verifier: randomValue(), state: randomValue())
    }

    var challenge: String { Self.encode(Data(SHA256.hash(data: Data(verifier.utf8)))) }

    static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    struct Callback { let url: URL; let redirectURI: URL }

    func code(_ callback: Callback) throws -> String {
        guard callback.url.scheme == callback.redirectURI.scheme,
              callback.url.host == callback.redirectURI.host,
              callback.url.path == callback.redirectURI.path,
              let parts = URLComponents(url: callback.url, resolvingAgainstBaseURL: false) else {
            throw BlitzReelsHandoffError.authorization
        }
        let items = parts.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state,
              !items.contains(where: { $0.name == "error" }),
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw BlitzReelsHandoffError.authorization
        }
        return code
    }
}

@MainActor
final class BlitzReelsBrowserAuthorization: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?

    struct Request { let url: URL; let callbackScheme: String }

    func authorize(_ request: Request) async throws -> URL {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let session = ASWebAuthenticationSession(url: request.url, callback: .customScheme(request.callbackScheme)) { [weak self] url, error in
                    Task { @MainActor in
                        if let url { self?.complete(.success(url)) }
                        else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                            self?.complete(.failure(CancellationError()))
                        } else { self?.complete(.failure(error ?? BlitzReelsHandoffError.authorization)) }
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self.session = session
                if !session.start() { complete(.failure(BlitzReelsHandoffError.authorization)) }
            }
        } onCancel: {
            Task { @MainActor in
                self.session?.cancel()
                self.complete(.failure(CancellationError()))
            }
        }
    }

    private func complete(_ result: Result<URL, Error>) {
        let pending = continuation
        continuation = nil
        session = nil
        pending?.resume(with: result)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

@MainActor
@Observable
final class BlitzReelsConnection {
    private(set) var account: BlitzReelsAccount?
    private(set) var selectedWorkspaceID: String?
    @ObservationIgnored let client: BlitzReelsHTTPClient
    @ObservationIgnored private let store: BlitzReelsCredentialStore
    @ObservationIgnored private let browser = BlitzReelsBrowserAuthorization()
    @ObservationIgnored private var refreshTask: Task<String, Error>?

    init(client: BlitzReelsHTTPClient) {
        self.client = client
        self.store = .init(origin: client.origin)
        selectedWorkspaceID = UserDefaults.standard.string(forKey: "BlitzReelsWorkspace:\(client.origin.absoluteString)")
    }

    var hasCredential: Bool { store.load() != nil }
    var selectedWorkspace: BlitzReelsWorkspace? {
        account?.workspaces.first { $0.id == selectedWorkspaceID }
    }

    func selectWorkspace(_ id: String) {
        guard account?.workspaces.contains(where: { $0.id == id }) == true else { return }
        selectedWorkspaceID = id
        UserDefaults.standard.set(id, forKey: "BlitzReelsWorkspace:\(client.origin.absoluteString)")
    }

    func connect() async throws {
        if !hasCredential { try await signIn() }
        try await reload()
    }

    func reload() async throws {
        let result: BlitzReelsAccount
        do {
            result = try await send(.init(path: "api/blitzrecorder/connection", method: "GET", key: nil, body: nil))
        } catch {
            account = nil
            throw error
        }
        account = result
        if !result.workspaces.contains(where: { $0.id == selectedWorkspaceID }),
           let workspace = result.workspaces.first(where: { $0.id == result.default_workspace_id }) ?? result.workspaces.first {
            selectWorkspace(workspace.id)
        }
    }

    func disconnect() async throws {
        guard let credential = store.load() else { account = nil; return }
        struct Revoked: Decodable { }
        do {
            let _: Revoked = try await send(.init(
                path: "api/blitzrecorder/connection/revoke", method: "POST", key: nil,
                body: ["client_id": credential.clientID]
            ))
        } catch BlitzReelsHandoffError.signInAgain {
        }
        store.clear()
        account = nil
    }

    func send<Response: Decodable>(_ request: BlitzReelsHTTPRequest) async throws -> Response {
        let token = try await accessToken(forceRefresh: false)
        func authorized(_ token: String) -> BlitzReelsHTTPRequest {
            .init(path: request.path, method: request.method, key: token, body: request.body, idempotencyKey: request.idempotencyKey)
        }
        do { return try await client.send(authorized(token)) }
        catch BlitzReelsHandoffError.signInAgain {
            let renewed = try await accessToken(forceRefresh: true)
            do { return try await client.send(authorized(renewed)) }
            catch BlitzReelsHandoffError.signInAgain {
                store.clear()
                account = nil
                throw BlitzReelsHandoffError.signInAgain
            }
        }
    }

    private struct Discovery: Decodable {
        let authorization_endpoint: URL
    }
    private struct Registration: Decodable { let client_id: String }
    private struct Token: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double
    }

    private func signIn() async throws {
        let discovery: Discovery = try await client.send(.init(
            path: ".well-known/oauth-authorization-server", method: "GET", key: nil, body: nil
        ))
        guard discovery.authorization_endpoint.scheme == "https" else { throw BlitzReelsHandoffError.authorization }
        let scheme = Bundle.main.bundleIdentifier?.hasSuffix(".debug") == true ? "blitzrecorder-dev" : "blitzrecorder"
        let redirect = URL(string: "\(scheme)://oauth/callback")!
        let registrationKey = "BlitzReelsOAuthClient:\(client.origin.absoluteString):\(scheme)"
        let clientID: String
        if let saved = UserDefaults.standard.string(forKey: registrationKey) {
            clientID = saved
        } else {
            let registration: Registration = try await client.send(.init(
                path: "api/oauth/register", method: "POST", key: nil,
                body: [
                    "client_name": "BlitzRecorder", "client_uri": client.origin.appendingPathComponent("blitzrecorder").absoluteString,
                    "redirect_uris": [redirect.absoluteString], "grant_types": ["authorization_code", "refresh_token"],
                    "response_types": ["code"], "token_endpoint_auth_method": "none",
                    "scope": "openid email profile"
                ]
            ))
            clientID = registration.client_id
            UserDefaults.standard.set(clientID, forKey: registrationKey)
        }
        let proof = try BlitzReelsOAuthProof.make()
        var url = URLComponents(url: discovery.authorization_endpoint, resolvingAgainstBaseURL: false)!
        url.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirect.absoluteString),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: "openid email profile"),
            .init(name: "state", value: proof.state), .init(name: "code_challenge", value: proof.challenge),
            .init(name: "code_challenge_method", value: "S256")
        ]
        let callback = try await browser.authorize(.init(url: url.url!, callbackScheme: scheme))
        let code = try proof.code(.init(url: callback, redirectURI: redirect))
        let token: Token = try await client.send(.init(
            path: "api/oauth/token", method: "POST", key: nil,
            body: [
                "grant_type": "authorization_code", "client_id": clientID,
                "redirect_uri": redirect.absoluteString, "code": code, "code_verifier": proof.verifier
            ]
        ))
        guard let refresh = token.refresh_token, !refresh.isEmpty else { throw BlitzReelsHandoffError.authorization }
        try store.save(.init(clientID: clientID, accessToken: token.access_token, refreshToken: refresh,
                             expiresAt: Date().addingTimeInterval(token.expires_in)))
    }

    private func accessToken(forceRefresh: Bool) async throws -> String {
        if let refreshTask { return try await refreshTask.value }
        guard let credential = store.load() else { throw BlitzReelsHandoffError.signInAgain }
        if !forceRefresh && credential.expiresAt.timeIntervalSinceNow > 60 { return credential.accessToken }
        let task = Task<String, Error> {
            let token: Token = try await client.send(.init(
                path: "api/oauth/token", method: "POST", key: nil,
                body: ["grant_type": "refresh_token", "client_id": credential.clientID, "refresh_token": credential.refreshToken]
            ))
            try store.save(.init(clientID: credential.clientID, accessToken: token.access_token,
                                 refreshToken: token.refresh_token ?? credential.refreshToken,
                                 expiresAt: Date().addingTimeInterval(token.expires_in)))
            return token.access_token
        }
        refreshTask = task
        defer { refreshTask = nil }
        do { return try await task.value }
        catch BlitzReelsHandoffError.signInAgain {
            store.clear()
            account = nil
            throw BlitzReelsHandoffError.signInAgain
        }
    }
}
