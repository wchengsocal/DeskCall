import Foundation

/// Configuration shared by the app and the Call Directory extension.
///
/// The base URL has three sources, in priority order:
///   1. a URL the user typed in Settings (shared via the app group, when one is available)
///   2. the `DeskCallAPIBaseURL` key baked into each target's Info.plist
///   3. localhost, so a debug build talks to a laptop running the FastAPI server
enum AppConfig {
    static let infoPlistURLKey = "DeskCallAPIBaseURL"
    static let infoPlistGroupKey = "DeskCallAppGroup"
    static let storedURLKey = "api.baseURL"
    static let storedClientKey = "api.clientKey"

    static var appGroupIdentifier: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: infoPlistGroupKey) as? String,
              !group.isEmpty else { return nil }
        // An app group the signing profile does not grant resolves to nil here,
        // which is the expected case for a free-account sideload.
        guard FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group) != nil else { return nil }
        return group
    }

    static var sharedDefaults: UserDefaults? {
        guard let group = appGroupIdentifier else { return nil }
        return UserDefaults(suiteName: group)
    }

    static var bakedBaseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: infoPlistURLKey) as? String,
           let url = URL(string: raw), url.host != nil {
            return url
        }
        return URL(string: "http://127.0.0.1:8000")!
    }

    static var baseURL: URL {
        if let raw = sharedDefaults?.string(forKey: storedURLKey),
           let url = URL(string: raw), url.host != nil {
            return url
        }
        return bakedBaseURL
    }

    static var clientKey: String? {
        sharedDefaults?.string(forKey: storedClientKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func setBaseURL(_ raw: String) {
        sharedDefaults?.set(raw, forKey: storedURLKey)
        UserDefaults.standard.set(raw, forKey: storedURLKey)
    }

    static func setClientKey(_ raw: String) {
        sharedDefaults?.set(raw, forKey: storedClientKey)
        UserDefaults.standard.set(raw, forKey: storedClientKey)
    }

    /// The app can always read its own copy, even when no app group is granted.
    static var localBaseURLString: String {
        UserDefaults.standard.string(forKey: storedURLKey) ?? bakedBaseURL.absoluteString
    }

    static var localClientKey: String {
        UserDefaults.standard.string(forKey: storedClientKey) ?? ""
    }
}
