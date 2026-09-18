import Foundation

@MainActor
enum Settings {
    static let defaultBaseURL = "http://localhost:8025"
    private static let baseURLKey = "mailpitBaseURL"

    static var baseURLString: String {
        get { UserDefaults.standard.string(forKey: baseURLKey) ?? defaultBaseURL }
        set { UserDefaults.standard.set(newValue, forKey: baseURLKey) }
    }

    /// Normalised base URL: scheme + host + optional port + optional webroot path, no trailing slash.
    static var baseURL: URL {
        var raw = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.contains("://") { raw = "http://" + raw }
        while raw.hasSuffix("/") { raw.removeLast() }
        return URL(string: raw) ?? URL(string: defaultBaseURL)!
    }

    static func webURL(path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    static func messageURL(id: String) -> URL {
        webURL(path: "view/\(id)")
    }

    static var eventsURL: URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = (components.scheme == "https") ? "wss" : "ws"
        components.path = (components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path) + "/api/events"
        return components.url!
    }
}
