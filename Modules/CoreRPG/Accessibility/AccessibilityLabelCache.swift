// @copyright André Trettin

import SwiftUI

/// Thread-safe cache for accessibility labels of SF Symbols
/// Reduces repeated localization and accessibility label generation overhead
@MainActor
public final class AccessibilityLabelCache {
    public static let shared = AccessibilityLabelCache()

    private var cache: [String: String] = [:]

    private init() {}

    /// Get cached accessibility label for an SF Symbol name
    /// Falls back to system generation if not cached
    public func label(for systemName: String) -> String? {
        // Return cached label if available
        if let cached = cache[systemName] {
            return cached
        }

        // Generate label using SwiftUI's Image and cache it
        // This happens once per symbol, then the cache takes over
        _ = Image(systemName: systemName)

        // Access the underlying UIImage to get the accessibility label
        // This triggers the expensive AXSSAccessibilityDescriptionForSymbolName path
        // but only once per unique symbol
        #if os(iOS) || os(tvOS) || os(visionOS)
        if let uiImage = UIImage(systemName: systemName),
           let accessibilityLabel = uiImage.accessibilityLabel {
            cache[systemName] = accessibilityLabel
            return accessibilityLabel
        }
        #elseif os(macOS)
        if let nsImage = NSImage(systemSymbolName: systemName, accessibilityDescription: nil),
           let accessibilityLabel = nsImage.accessibilityDescription {
            cache[systemName] = accessibilityLabel
            return accessibilityLabel
        }
        #endif

        // Fallback: cache the system name itself
        cache[systemName] = systemName
        return systemName
    }

    /// Clear the cache (useful for memory pressure or testing)
    public func clearCache() {
        cache.removeAll()
    }

    /// Get cache statistics for monitoring
    public var cacheStats: (count: Int, symbols: [String]) {
        (cache.count, Array(cache.keys.sorted()))
    }
}

/// View modifier to apply cached accessibility label to Image views
struct CachedAccessibilityLabel: ViewModifier {
    let systemName: String

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(AccessibilityLabelCache.shared.label(for: systemName) ?? systemName)
    }
}

extension Image {
    /// Convenience method to create an Image with cached accessibility label
    @MainActor
    static func cachedSymbol(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .modifier(CachedAccessibilityLabel(systemName: systemName))
    }
}
