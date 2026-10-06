import Foundation

/// On-device storage for everything the Call Directory extension needs at refresh time.
///
/// When the signing profile grants an app group, the payload lands in the shared
/// container and the extension reads it directly. Without an app group -- the
/// normal case for a free-Apple-ID sideload -- the extension falls back to
/// fetching the blocklist over the network, so saved identities are the only
/// thing lost.
struct DirectoryPayload: Codable {
    var identified: [DirectoryEntry] = []
    var blocked: [Int64] = []
    var updatedAt: Date = .distantPast
    var version: String = ""

    /// CallKit requires strictly ascending, de-duplicated numbers in both lists.
    func normalized() -> DirectoryPayload {
        var copy = self
        var seen = Set<Int64>()
        copy.identified = identified
            .sorted { $0.number < $1.number }
            .filter { seen.insert($0.number).inserted }
        copy.blocked = Array(Set(blocked)).sorted()
        return copy
    }
}

enum SharedStore {
    static let fileName = "directory.json"

    static var sharedFileURL: URL? {
        guard let group = AppConfig.appGroupIdentifier else { return nil }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent(fileName)
    }

    static var localFileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(fileName)
    }

    static func load() -> DirectoryPayload {
        for url in [sharedFileURL, localFileURL].compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: url),
                  let payload = try? JSONDecoder().decode(DirectoryPayload.self, from: data)
            else { continue }
            return payload
        }
        return DirectoryPayload()
    }

    @discardableResult
    static func save(_ payload: DirectoryPayload) -> Bool {
        guard let data = try? JSONEncoder().encode(payload.normalized()) else { return false }
        var wroteAnywhere = false
        for url in [sharedFileURL, localFileURL].compactMap({ $0 }) {
            let parent = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            if (try? data.write(to: url, options: .atomic)) != nil {
                wroteAnywhere = true
            }
        }
        return wroteAnywhere
    }
}
