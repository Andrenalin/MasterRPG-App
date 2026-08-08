// @copyright André Trettin

import Foundation

/// Actor-based resource cache for async file loading
/// Eliminates main thread blocking and reduces I/O overhead
@MainActor
public final class ResourceCache: Sendable {
    /// Shared singleton instance
    public static let shared = ResourceCache()

    /// Private cache storage
    private var dataCache: [String: Data] = [:]
    private var inFlightRequests: [String: Task<Data, Error>] = [:]

    private init() {}

    /// Load resource data asynchronously, using cache if available
    /// - Parameters:
    ///   - key: Unique identifier for the resource
    ///   - url: URL to load from if not cached
    /// - Returns: Resource data
    public func load(key: String, from url: URL) async throws -> Data {
        // Check cache first
        if let cached = dataCache[key] {
            PerformanceTrace.event("ResourceCacheHit", source: key, count: cached.count)
            return cached
        }
        PerformanceTrace.event("ResourceCacheMiss", source: key, count: 0)

        // Check if already loading
        if let inFlight = inFlightRequests[key] {
            return try await inFlight.value
        }

        // Start new load task
        let trace = PerformanceTrace.begin("ResourceLoad", source: key, count: 0)
        let task = Task.detached(name: "Resource Cache Load", priority: .utility) {
            try Data(contentsOf: url)
        }

        inFlightRequests[key] = task

        do {
            let data = try await task.value
            trace?.end()
            dataCache[key] = data
            inFlightRequests.removeValue(forKey: key)
            // `task` is shared: concurrent callers for the same key await this same
            // in-flight task, so it must run to completion — and its result cached —
            // regardless of any one caller's own cancellation. Stopping it would break
            // the other callers, and skipping the bookkeeping above would leave
            // `inFlightRequests[key]` pointing at an already-finished task forever,
            // permanently bypassing `dataCache` for this key. What a cancelled caller
            // shouldn't do is return this value as if it succeeded, so check and
            // propagate its own cancellation only now that bookkeeping is settled.
            try Task.checkCancellation()
            return data
        } catch is CancellationError {
            // Bookkeeping above already ran (or didn't need to — see the `catch` below
            // for the case where `task.value` itself threw); don't touch `trace`/
            // `inFlightRequests` a second time here.
            throw CancellationError()
        } catch {
            trace?.end()
            inFlightRequests.removeValue(forKey: key)
            throw error
        }
    }

    /// Preload multiple resources in parallel
    /// - Parameter resources: Dictionary of keys to URLs
    public func preload(_ resources: [String: URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for (key, url) in resources {
                group.addTask {
                    _ = try? await self.load(key: key, from: url)
                }
            }
        }
    }

    /// Clear specific cache entry
    /// - Parameter key: Key to remove
    public func clear(key: String) {
        dataCache.removeValue(forKey: key)
        inFlightRequests[key]?.cancel()
        inFlightRequests.removeValue(forKey: key)
    }

    /// Clear all cached data
    public func clearAll() {
        dataCache.removeAll()
        for task in inFlightRequests.values {
            task.cancel()
        }
        inFlightRequests.removeAll()
    }

    /// Get current cache size
    public var cacheSize: Int {
        dataCache.values.reduce(0) { $0 + $1.count }
    }

    /// Get number of cached items
    public var itemCount: Int {
        dataCache.count
    }
}

/// Extension for Bundle resource loading
public extension Bundle {
    /// Load resource asynchronously using ResourceCache
    /// - Parameters:
    ///   - name: Resource name
    ///   - ext: File extension
    /// - Returns: Resource data
    func asyncLoadResource(name: String, extension ext: String) async throws -> Data {
        guard let url = self.url(forResource: name, withExtension: ext) else {
            throw ResourceCacheError.resourceNotFound(name: name, extension: ext)
        }

        let key = "\(bundleIdentifier ?? "unknown").\(name).\(ext)"
        return try await ResourceCache.shared.load(key: key, from: url)
    }

    /// Load resource asynchronously using ResourceCache with URL
    /// - Parameter url: Resource URL
    /// - Returns: Resource data
    func asyncLoadResource(url: URL) async throws -> Data {
        let key = "\(bundleIdentifier ?? "unknown").\(url.lastPathComponent)"
        return try await ResourceCache.shared.load(key: key, from: url)
    }
}

/// Errors for ResourceCache
public enum ResourceCacheError: Error {
    case resourceNotFound(name: String, extension: String)
    case loadFailed(URL, Error)
}
