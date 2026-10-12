import Foundation

public enum PhoneSearchEngine: String, CaseIterable, Identifiable, Sendable {
    case google
    case bing
    case duckDuckGo

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .google: "Google"
        case .bing: "Bing"
        case .duckDuckGo: "DuckDuckGo"
        }
    }

    public func searchURL(query: String) -> URL? {
        var components: URLComponents?
        switch self {
        case .google:
            components = URLComponents(string: "https://www.google.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: query)]
        case .bing:
            components = URLComponents(string: "https://www.bing.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: query)]
        case .duckDuckGo:
            components = URLComponents(string: "https://html.duckduckgo.com/html/")
            components?.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        return components?.url
    }
}

public struct PhoneSearchEnginePreferences: Equatable, Sendable {
    public static let primaryDefaultsKey = "openmuse.phoneSearch.primaryEngine"
    public static let fallbackDefaultsKey = "openmuse.phoneSearch.fallbackEngine"

    public let primary: PhoneSearchEngine
    public let fallback: PhoneSearchEngine?

    public init(primary: PhoneSearchEngine = .google, fallback: PhoneSearchEngine? = nil) {
        self.primary = primary
        self.fallback = fallback == primary ? nil : fallback
    }

    public init(userDefaults: UserDefaults = .standard) {
        let primary = userDefaults.string(forKey: Self.primaryDefaultsKey)
            .flatMap(PhoneSearchEngine.init(rawValue:)) ?? .google
        let fallback: PhoneSearchEngine?
        if let storedFallback = userDefaults.object(forKey: Self.fallbackDefaultsKey) as? String {
            // An explicitly saved empty value means the user turned fallback off.
            fallback = storedFallback.isEmpty ? nil : PhoneSearchEngine(rawValue: storedFallback)
        } else {
            // Google remains the preferred engine; Bing is the China-friendly
            // out-of-box fallback unless the user explicitly changes the picker.
            fallback = primary == .google ? .bing : .google
        }
        self.init(primary: primary, fallback: fallback)
    }

    public var enginesToTry: [PhoneSearchEngine] {
        [primary] + (fallback.map { [$0] } ?? [])
    }
}
