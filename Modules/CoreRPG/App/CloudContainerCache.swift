// @copyright André Trettin

import Foundation
import Synchronization

/// Caches the iCloud ubiquity container URL and drops it when the iCloud identity changes,
/// so the next read resolves it again. See CODE_AUDIT_18 §3.3.
final class CloudContainerCache: Sendable {
    static let shared = CloudContainerCache()

    private enum Resolution: Sendable {
        case unresolved
        case resolved(URL?)
    }

    private struct State: Sendable {
        var resolution: Resolution = .unresolved
        /// Bumped by `invalidate()`. A resolve that started before the bump must not store its
        /// (old-identity) result. See CODE_AUDIT_19 §3.8.
        var generation = 0
    }

    private let state = Mutex(State())
    private let isObserving = Mutex(false)

    var url: URL? {
        let (resolution, generation) = state.withLock { ($0.resolution, $0.generation) }
        if case .resolved(let url) = resolution {
            return url
        }
        // Resolved outside the lock: the call can block while the container is set up.
        let url = FileManager.default.url(forUbiquityContainerIdentifier: FileManager.cloudContainerIdentifier)
        state.withLock { state in
            guard state.generation == generation else { return }
            state.resolution = .resolved(url)
        }
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
        state.withLock { state in
            state.resolution = .unresolved
            state.generation += 1
        }
    }
}
