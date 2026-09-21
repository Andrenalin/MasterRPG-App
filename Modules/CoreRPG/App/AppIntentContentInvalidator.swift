// @copyright André Trettin

import Foundation

@MainActor
public enum AppIntentContentInvalidator {
    private static var refreshShortcutParameters: (@MainActor @Sendable () -> Void)?
    private static var reindexContent: (@MainActor @Sendable () async -> Void)?
    private static var reindexTask: Task<Void, Never>?

    public static func configure(
        refreshShortcutParameters: (@escaping @MainActor @Sendable () -> Void),
        reindexContent: (@escaping @MainActor @Sendable () async -> Void)
    ) {
        Self.refreshShortcutParameters = refreshShortcutParameters
        Self.reindexContent = reindexContent
    }

    /// Debounces shortcut-parameter refresh and reindexing behind one tracked task. The reindex
    /// is awaited inside it, so a newer `invalidate()` cancels a run that is still in flight
    /// instead of piling overlapping reindexes onto the main actor during bulk edits, imports
    /// or sync. See CODE_AUDIT_16 §3.6.
    public static func invalidate() {
        reindexTask?.cancel()
        reindexTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            refreshShortcutParameters?()
            await reindexContent?()
        }
    }
}
