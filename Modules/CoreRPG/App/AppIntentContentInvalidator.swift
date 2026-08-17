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

    public static func invalidate() {
        refreshShortcutParameters?()
        reindexTask?.cancel()
        reindexTask = delayedTask(.seconds(1)) {
            Task { await reindexContent?() }
        }
    }
}
