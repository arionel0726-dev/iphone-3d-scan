import Foundation

/// Talks to the existing 2-3d-store Bun/Hono API. No parallel auth system:
/// every authenticated request carries the Better Auth bearer token this
/// client obtained from POST /api/auth/sign-in/email, exactly the same
/// token the web app's own bearer-plugin flow uses (see auth.test.ts in
/// the back repo).
final class APIClient {
    static let shared = APIClient()

    let baseURL: URL
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session

        if let configured = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
            let url = URL(string: configured), !configured.isEmpty
        {
            baseURL = url
        } else {
            // Fallback for local development only; override via the
            // APIBaseURL Info.plist key (see README) for a real device
            // talking to a real backend.
            baseURL = URL(string: "http://localhost:3001")!
        }
    }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws -> SignInUser {
        struct Body: Encodable { var email: String; var password: String; var rememberMe: Bool }
        let body = Body(email: email, password: password, rememberMe: true)
        let response: SignInResponse = try await request(
            path: "/api/auth/sign-in/email",
            method: "POST",
            body: body,
            requiresAuth: false
        )

        guard let token = response.token, let user = response.user else {
            throw APIError.server(status: 200, message: "Сервер не вернул токен авторизации.")
        }

        KeychainTokenStore.save(token)
        return user
    }

    /// GET /api/auth/get-session — the same endpoint the web app uses to
    /// check whether a stored session is still valid. Returns nil both when
    /// there is no local token and when the server no longer recognizes it
    /// (expired/revoked) rather than throwing, since "not signed in" is the
    /// expected outcome on first launch.
    func fetchCurrentSession() async -> SignInUser? {
        guard isSignedIn else { return nil }
        struct SessionResponse: Decodable { var user: SignInUser? }
        guard let response: SessionResponse = try? await request(
            path: "/api/auth/get-session",
            method: "GET",
            body: Optional<Int>.none
        ) else {
            return nil
        }
        return response.user
    }

    func signOut() async {
        _ = try? await requestRaw(path: "/api/auth/sign-out", method: "POST", body: Optional<Int>.none)
        KeychainTokenStore.clear()
    }

    var isSignedIn: Bool { KeychainTokenStore.read() != nil }

    // MARK: - Stores

    func fetchStores() async throws -> [Store] {
        let response: StoresResponse = try await request(path: "/api/stores", method: "GET", body: Optional<Int>.none)
        return response.stores
    }

    // MARK: - Scans

    func uploadScan(_ dto: ScanUploadDTO) async throws -> ScanDraftSummary {
        let response: ScanUploadResponse = try await request(path: "/api/scans", method: "POST", body: dto)
        return response.scan
    }

    // MARK: - Request plumbing

    private func request<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body?,
        requiresAuth: Bool = true
    ) async throws -> Response {
        let data = try await requestRaw(path: path, method: method, body: body, requiresAuth: requiresAuth)
        do {
            return try ScanDTOEncoding.makeDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    @discardableResult
    private func requestRaw<Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        requiresAuth: Bool = true
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if requiresAuth {
            guard let token = KeychainTokenStore.read() else {
                throw APIError.notAuthenticated
            }
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            urlRequest.httpBody = try ScanDTOEncoding.makeEncoder().encode(body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
            throw APIError.network(urlError.localizedDescription)
        } catch {
            throw APIError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.network("Сервер не ответил.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                KeychainTokenStore.clear()
                throw APIError.sessionExpired
            }
            let parsedMessage = (try? JSONDecoder().decode(APIErrorBody.self, from: data))
            let message = parsedMessage?.error ?? parsedMessage?.message ?? ""
            throw APIError.server(status: httpResponse.statusCode, message: message)
        }

        return data
    }
}
