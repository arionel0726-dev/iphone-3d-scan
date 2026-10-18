import Combine
import Foundation

/// Root screen the app is on. Scanning always targets a chosen store and
/// optionally an existing layout (targetLayoutId), matching the backend's
/// POST /api/scans contract — nil means "create a new layout from this
/// scan" on the web review screen, exactly like the web app's own scan
/// review flow.
enum AppScreen: Equatable {
    case checkingSession
    case login
    case storePicker
    case scanning(store: Store, targetLayout: LayoutSummary?)
    case uploadResult(UploadOutcome)
}

enum UploadOutcome: Equatable {
    /// `isDemo` is purely a local UI flag (never part of the wire DTO): it
    /// tells UploadResultView to visibly label the result as test data from
    /// the Debug-only demo-scan path, never a real RoomPlan capture.
    case success(scanId: UUID, reviewURLBase: URL, isDemo: Bool)
    case failure(String)
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var screen: AppScreen = .checkingSession
    @Published private(set) var currentUserName: String?
    @Published var stores: [Store] = []
    @Published var storesLoadError: String?
    @Published var isLoadingStores = false

    private let api: APIClient

    /// Base URL for the web review screen (/scans/:id) the manager opens
    /// after a successful upload. Configurable via the WebAppBaseURL
    /// Info.plist key (see README); falls back to the same local-dev host
    /// as APIBaseURL's own fallback.
    let reviewURLBase: URL

    init(api: APIClient = .shared) {
        self.api = api
        if let configured = Bundle.main.object(forInfoDictionaryKey: "WebAppBaseURL") as? String,
            let url = URL(string: configured), !configured.isEmpty
        {
            reviewURLBase = url
        } else {
            reviewURLBase = URL(string: "http://localhost:3000")!
        }
    }

    func bootstrap() async {
        screen = .checkingSession
        if let user = await api.fetchCurrentSession() {
            currentUserName = user.name.isEmpty ? user.email : user.name
            screen = .storePicker
            await loadStores()
        } else {
            currentUserName = nil
            screen = .login
        }
    }

    func signIn(email: String, password: String) async throws {
        let user = try await api.signIn(email: email, password: password)
        currentUserName = user.name.isEmpty ? user.email : user.name
        screen = .storePicker
        await loadStores()
    }

    func signOut() async {
        await api.signOut()
        currentUserName = nil
        stores = []
        screen = .login
    }

    /// Any API call can discover the session expired (HTTP 401). Routes
    /// back to the login screen with a message instead of a stuck spinner.
    func handleSessionExpired() {
        currentUserName = nil
        stores = []
        screen = .login
    }

    func loadStores() async {
        isLoadingStores = true
        storesLoadError = nil
        defer { isLoadingStores = false }
        do {
            stores = try await api.fetchStores()
        } catch APIError.sessionExpired {
            handleSessionExpired()
        } catch {
            storesLoadError = error.localizedDescription
        }
    }

    func beginScan(store: Store, targetLayout: LayoutSummary?) {
        screen = .scanning(store: store, targetLayout: targetLayout)
    }

    func cancelScan() {
        screen = .storePicker
    }

    func finishScan(outcome: UploadOutcome) {
        screen = .uploadResult(outcome)
    }

    func returnToStorePicker() {
        screen = .storePicker
        Task { await loadStores() }
    }

    var apiClient: APIClient { api }
}
