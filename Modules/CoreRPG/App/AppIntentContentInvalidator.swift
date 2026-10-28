// @copyright André Trettin

import Foundation

@MainActor
public enum AppIntentContentInvalidator {
    private static var reindexContent: (@MainActor @Sendable () async -> Void)?
    private static var debounceTask: Task<Void, Never>?
    private static var reindexTask: Task<Void, Never>?
    private static var reindexAgain = false

    public static func configure(reindexContent: (@escaping @MainActor @Sendable () async -> Void)) {
        Self.reindexContent = reindexContent
    }

    /// Debounces the reindex of what changed (each item controller marks its own ids on its
    /// `ItemDataModel`, and `reindexContent` takes them). A newer `invalidate()` only restarts the
    /// debounce: a reindex that is already running is never cancelled, because the ids it took
    /// would be lost, and instead runs again for what changed meanwhile. Bursts of saves, imports
    /// and sync batches therefore cost one pass over the changed items. The reindex runs in its own
    /// task, started without a suspension after the debounce, so cancelling the debounce can never
    /// reach it. See CODE_AUDIT_16 §3.6, CODE_AUDIT_AppIntents §7.1, CODE_AUDIT_Since_3.0.1 §3.3.
    public static func invalidate() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            startReindex()
        }
    }

    private static func startReindex() {
        guard reindexTask == nil else {
            reindexAgain = true
            return
        }
        reindexTask = Task { @MainActor in
            repeat {
                reindexAgain = false
                await reindexContent?()
            } while reindexAgain
            reindexTask = nil
        }
    }
}
