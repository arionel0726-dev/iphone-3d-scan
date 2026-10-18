import Foundation

/// Every state the UI needs to tell apart for requirement #7: lost network,
/// expired session, and "the API said no" each get a distinct, translatable
/// message instead of one generic "something went wrong".
enum APIError: Error, LocalizedError, Equatable {
    case invalidURL
    case notAuthenticated
    /// The device has no usable network path (Wi-Fi/cellular down, airplane
    /// mode, DNS failure, timeout) — distinct from the server rejecting
    /// the request.
    case network(String)
    case decoding(String)
    /// The session/bearer token is missing, invalid, or expired (HTTP 401).
    case sessionExpired
    case server(status: Int, message: String)

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL), (.notAuthenticated, .notAuthenticated),
            (.sessionExpired, .sessionExpired):
            return true
        case let (.network(a), .network(b)): return a == b
        case let (.decoding(a), .decoding(b)): return a == b
        case let (.server(sa, ma), .server(sb, mb)): return sa == sb && ma == mb
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Некорректный адрес сервера. Проверьте настройки приложения."
        case .notAuthenticated:
            return "Вы не вошли в аккаунт."
        case .network:
            return "Нет соединения с сервером. Проверьте интернет-подключение и повторите попытку."
        case .decoding:
            return "Сервер прислал неожиданный ответ. Попробуйте ещё раз позже."
        case .sessionExpired:
            return "Сессия истекла. Войдите в аккаунт ещё раз."
        case let .server(status, message):
            if status == 409 {
                return "Планировка изменилась на сервере. Обновите данные и повторите."
            }
            if let translated = Self.knownMessages[message] {
                return translated
            }
            return message.isEmpty ? "Сервер вернул ошибку (\(status))." : message
        }
    }

    /// Mirrors front/src/lib/api.ts's getApiErrorMessage dictionary on the
    /// web app, so the same backend error text reads the same way in both
    /// clients instead of showing raw English here.
    private static let knownMessages: [String: String] = [
        "Authentication required": "Требуется войти в аккаунт",
        "Authentication unavailable": "Сервис авторизации временно недоступен",
        "Invalid email or password": "Неверная электронная почта или пароль",
        "Invalid credentials": "Неверная электронная почта или пароль",
        "Invalid password": "Неверная электронная почта или пароль",
        "User not found": "Неверная электронная почта или пароль",
        "Store not found": "Магазин не найден",
        "Layout not found": "Планировка не найдена",
        "Scan not found": "Скан не найден",
        "Internal server error": "Внутренняя ошибка сервера",
    ]
}
