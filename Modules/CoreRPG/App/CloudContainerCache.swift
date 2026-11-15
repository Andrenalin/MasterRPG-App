// @copyright André Trettin

import Foundation
import Synchronization

/// Caches the iCloud ubiquity container URL and drops it when the iCloud identity changes,
/// so the next read resolves it again. See CODE_AUDIT_18 §3.3.
final class CloudContainerCache: Sendable {
    static let shared = CloudContainerCache()

    /// How long a missing container is believed while an iCloud identity exists. The system
    /// documents that `url(forUbiquityContainerIdentifier:)` can return nil while the container is
    /// still being provisioned (first launch after sign-in), and nothing signals when it is ready,
    /// so the lookup is retried after this interval. See CODE_AUDIT_26 §5.11.
    static let retryInterval: Duration = .seconds(5)

    private let hasIdentity: @Sendable () -> Bool
    private let resolveContainer: @Sendable () -> URL?
    private let retryInterval: Duration
    private let now: @Sendable () -> ContinuousClock.Instant

    init(
        hasIdentity: @escaping @Sendable () -> Bool = { FileManager.default.ubiquityIdentityToken != nil },
        resolveContainer: @escaping @Sendable () -> URL? = { FileManager.default.url(forUbiquityContainerIdentifier: FileManager.cloudContainerIdentifier) },
        retryInterval: Duration = CloudContainerCache.retryInterval,
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.hasIdentity = hasIdentity
        self.resolveContainer = resolveContainer
        self.retryInterval = retryInterval
        self.now = now
    }

    private enum Resolution: Sendable {
        case unresolved
        case resolved(URL?)
    }

    private struct State: Sendable {
        var resolution: Resolution = .unresolved
        /// Bumped by `invalidate()`. A resolve that started before the bump must not store its
        /// (old-identity) result. See CODE_AUDIT_19 §3.8.
        var generation = 0
        /// When a nil container was stored although an iCloud identity exists; such a result is
        /// retried after `retryInterval` instead of being believed for the whole run.
        var missingSince: ContinuousClock.Instant?
    }

    private let state = Mutex(State())
    private let isObserving = Mutex(false)

    /// Serializes the blocking system call. Concurrent first readers each used to call it
    /// themselves; the system then made a higher-QoS caller wait inside the call on a thread at a
    /// lower QoS (a priority inversion the runtime reports). Waiting on this lock instead
    /// donates the waiter's priority to the thread doing the work, and the system call runs once.
    private let resolveLock = Mutex(())

    var url: URL? {
        if let url = cachedUrl { return url.value }
        return resolveLock.withLock { _ in
            // Another reader may have resolved it while this one waited.
            if let url = cachedUrl { return url.value }
            let generation = state.withLock { $0.generation }
            // Not under `state`'s lock, so `invalidate()` never waits for the call, which can
            // block while the container is set up.
            // Without an iCloud identity there is no container, and the check does not block: it
            // spares callers (tests, a device without iCloud) the system call, which waits on a
            // lower-QoS thread of the system's own. A later sign-in posts
            // `NSUbiquityIdentityDidChange`, which invalidates this result.
            let hasIdentity = hasIdentity()
            let url: URL? = hasIdentity ? resolveContainer() : nil
            let resolvedAt = now()
            state.withLock { state in
                guard state.generation == generation else { return }
                state.resolution = .resolved(url)
                state.missingSince = (hasIdentity && url == nil) ? resolvedAt : nil
            }
            return url
        }
    }

    /// The cached resolution, or `nil` when none is stored (the wrapped value may itself be nil).
    private var cachedUrl: CachedUrl? {
        state.withLock { state in
            guard case .resolved(let url) = state.resolution else { return nil }
            if url == nil, let missingSince = state.missingSince, now() - missingSince >= retryInterval {
                return nil
            }
            return CachedUrl(value: url)
        }
    }

    private struct CachedUrl: Sendable {
        let value: URL?
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
            Task(priority: .utility) { @concurrent in
                _ = CloudContainerCache.shared.url
            }
        }
    }

    func invalidate() {
        state.withLock { state in
            state.resolution = .unresolved
            state.missingSince = nil
            state.generation += 1
        }
    }
}
