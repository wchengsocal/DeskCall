import CallKit
import Foundation
import SwiftUI

/// App-wide state. History lives only in this device's own container and is
/// never uploaded; clearing it here is the whole of "delete my data".
@MainActor
final class LookupStore: ObservableObject {
    @Published var history: [CallerProfile] = []
    @Published var savedForCallerID: [DirectoryEntry] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var directoryStatus: String = "Not yet synced"
    @Published var appGroupAvailable: Bool = AppConfig.appGroupIdentifier != nil

    private let historyURL: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("history.json")

    private var api: DeskCallAPI {
        DeskCallAPI(baseURL: URL(string: AppConfig.localBaseURLString) ?? AppConfig.bakedBaseURL,
                    clientKey: AppConfig.localClientKey.isEmpty ? nil : AppConfig.localClientKey)
    }

    init() {
        loadHistory()
        savedForCallerID = SharedStore.load().identified
    }

    // MARK: - Lookup

    func lookup(_ raw: String) async -> CallerProfile? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let profile = try await api.lookup(number: trimmed)
            record(profile)
            return profile
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func reportSpam(_ profile: CallerProfile) async {
        do {
            try await api.reportSpam(number: profile.phoneNumber)
            directoryStatus = "Reported. Sync Caller ID to block it on this device."
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - History (local only)

    private func record(_ profile: CallerProfile) {
        history.removeAll { $0.phoneNumber == profile.phoneNumber }
        history.insert(profile, at: 0)
        if history.count > 100 { history = Array(history.prefix(100)) }
        persistHistory()
    }

    func deleteHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        persistHistory()
    }

    func clearHistory() {
        history = []
        persistHistory()
    }

    private func loadHistory() {
        guard let historyURL,
              let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([CallerProfile].self, from: data)
        else { return }
        history = decoded
    }

    private func persistHistory() {
        guard let historyURL, let data = try? JSONEncoder().encode(history) else { return }
        let parent = historyURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try? data.write(to: historyURL, options: .atomic)
    }

    // MARK: - Caller ID directory

    func isSavedForCallerID(_ profile: CallerProfile) -> Bool {
        guard let number = PhoneFormatter.asCallKitNumber(profile.phoneNumber) else {
            return false
        }
        return savedForCallerID.contains { $0.number == number }
    }

    func toggleCallerID(for profile: CallerProfile) {
        guard let number = PhoneFormatter.asCallKitNumber(profile.phoneNumber) else {
            lastError = "That number can't be added to the system caller ID list."
            return
        }
        if let index = savedForCallerID.firstIndex(where: { $0.number == number }) {
            savedForCallerID.remove(at: index)
        } else {
            savedForCallerID.append(DirectoryEntry(number: number, label: profile.callerIDLabel))
        }
        savedForCallerID.sort { $0.number < $1.number }
    }

    func removeFromCallerID(at offsets: IndexSet) {
        savedForCallerID.remove(atOffsets: offsets)
    }

    /// Writes the payload the extension reads, then asks iOS to reload it.
    func syncCallerID() async {
        isLoading = true
        defer { isLoading = false }

        var payload = DirectoryPayload(
            identified: savedForCallerID,
            blocked: [],
            updatedAt: Date(),
            version: "local"
        )

        do {
            let remote = try await api.fetchDirectory()
            payload.blocked = remote.blocked
            payload.version = remote.version
        } catch {
            directoryStatus = "Saved \(savedForCallerID.count) names, but the spam list "
                + "didn't download: \(error.localizedDescription)"
        }

        SharedStore.save(payload)
        await reloadExtension(identityCount: payload.identified.count,
                             blockedCount: payload.blocked.count)
    }

    private func reloadExtension(identityCount: Int, blockedCount: Int) async {
        let manager = CXCallDirectoryManager.sharedInstance
        let identifier = "com.deskcall.app.CallDirectory"

        do {
            try await manager.reloadExtension(withIdentifier: identifier)
            let summary = "\(identityCount) name\(identityCount == 1 ? "" : "s"), "
                + "\(blockedCount) blocked"
            directoryStatus = appGroupAvailable
                ? "Synced \(summary) · \(Date().formatted(date: .omitted, time: .shortened))"
                : "Synced spam blocking only (\(blockedCount)). Names need an App Group — see Settings."
        } catch {
            directoryStatus = "iOS refused the reload: \(error.localizedDescription). "
                + "Check Settings ▸ Apps ▸ Phone ▸ Call Blocking & Identification."
        }
    }

    func refreshExtensionStatus() async {
        let manager = CXCallDirectoryManager.sharedInstance
        let identifier = "com.deskcall.app.CallDirectory"
        do {
            let status = try await manager.enabledStatusForExtension(withIdentifier: identifier)
            switch status {
            case .enabled:
                directoryStatus = "Extension enabled in iOS Settings."
            case .disabled:
                directoryStatus = "Turn DeskCall on in Settings ▸ Apps ▸ Phone ▸ "
                    + "Call Blocking & Identification."
            case .unknown:
                directoryStatus = "iOS hasn't registered the extension yet. Sync once."
            @unknown default:
                directoryStatus = "Unknown extension state."
            }
        } catch {
            directoryStatus = "Couldn't read extension status: \(error.localizedDescription)"
        }
    }
}
