import CallKit
import Foundation
import os

/// Feeds DeskCall's data into iOS's own caller-ID database.
///
/// iOS runs this out-of-process with a tight memory and time budget, so the
/// work here stays deliberately small: read a prepared payload, hand it to
/// CallKit, return. It never sees the user's contacts or call log -- a Call
/// Directory extension is write-only by design, which is exactly why DeskCall
/// uses one.
final class CallDirectoryHandler: CXCallDirectoryProvider {
    private let log = Logger(subsystem: "com.deskcall.app", category: "CallDirectory")

    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self

        // Incremental refreshes are not supported; always replace the full set.
        if context.isIncremental {
            context.removeAllIdentificationEntries()
            context.removeAllBlockingEntries()
        }

        var payload = SharedStore.load().normalized()

        // Without an app group the shared file is unreachable, so pull the
        // blocklist straight from the API. Identified entries still require the
        // app group, since they come from the user's own saved lookups.
        if payload.blocked.isEmpty && payload.identified.isEmpty {
            if let remote = fetchRemoteDirectory() {
                payload = remote.normalized()
            }
        }

        for entry in payload.identified {
            context.addIdentificationEntry(withNextSequentialPhoneNumber: entry.number,
                                           label: String(entry.label.prefix(60)))
        }
        for number in payload.blocked {
            context.addBlockingEntry(withNextSequentialPhoneNumber: number)
        }

        log.info("loaded \(payload.identified.count) identities, \(payload.blocked.count) blocks")
        context.completeRequest()
    }

    /// Synchronous by necessity: `beginRequest` must finish before it returns.
    private func fetchRemoteDirectory() -> DirectoryPayload? {
        let api = DeskCallAPI()
        let semaphore = DispatchSemaphore(value: 0)
        var result: DirectoryPayload?

        Task {
            defer { semaphore.signal() }
            do {
                let remote = try await api.fetchDirectory()
                result = DirectoryPayload(
                    identified: remote.identified.map {
                        DirectoryEntry(number: $0.number, label: $0.label)
                    },
                    blocked: remote.blocked,
                    updatedAt: Date(),
                    version: remote.version
                )
            } catch {
                self.log.error("directory fetch failed: \(error.localizedDescription)")
            }
        }

        _ = semaphore.wait(timeout: .now() + 8)
        return result
    }
}

extension CallDirectoryHandler: CXCallDirectoryExtensionContextDelegate {
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext,
                       withError error: Error) {
        // Most failures here mean out-of-order numbers or an oversized payload.
        log.error("call directory request failed: \(error.localizedDescription)")
    }
}
