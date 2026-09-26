// @copyright André Trettin

import Foundation
import Synchronization

/// Caches the iCloud ubiquity container URL and drops it when the iCloud identity changes,
/// so the next read resolves it again. See CODE_AUDIT_18 §3.3.
final class CloudContainerCache: Sendable {
    static let shared = CloudContainerCache()

    private enum State: Sendable {
        case unresolved
        case resolved(URL?)
    }

    private let state = Mutex<State>(.unresolved)
    private let isObserving = Mutex(false)

    var url: URL? {
        if case .resolved(let url) = state.withLock({ $0 }) {
            return url
        }
        // Resolved outside the lock: the call can block while the container is set up.
        let url = FileManager.default.url(forUbiquityContainerIdentifier: FileManager.cloudContainerIdentifier)
        state.withLock { $0 = .resolved(url) }
        return url
    }

    func startObservingIdentityChanges() {
        let shouldStart = isObserving.withLock { observing -> Bool in
            defer { observing = true }
            return !observing
        }
        guard shouldStart else { return }
        _ = NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.invalidate()
            // Re-resolve off the posting (usually main) thread.
            Task.detached(priority: .utility) {
                _ = CloudContainerCache.shared.url
            }
        }
    }

    func invalidate() {
        state.withLock { $0 = .unresolved }
    }
}
