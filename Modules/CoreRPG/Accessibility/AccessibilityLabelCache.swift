// @copyright André Trettin

import SwiftUI

/// Thread-safe cache for accessibility labels of SF Symbols
/// Reduces repeated localization and accessibility label generation overhead
@MainActor
public final class AccessibilityLabelCache {
    public static let shared = AccessibilityLabelCache()

    private var cache: [String: String] = [:]

    private init() {
        // Pre-populate common toolbar symbols to avoid first-time overhead
        preloadCommonSymbols()
    }

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

    /// Pre-load accessibility labels for frequently used toolbar symbols
    private func preloadCommonSymbols() {
        // Common toolbar symbols from GameToolBar.swift and other toolbars
        let commonSymbols = [
            "arrow.left.square.fill",
            "arrow.right.square",
            "rectangle.3.offgrid.fill",
            "rectangle.lefthalf.inset.filled",
            "rectangle.3.offgrid",
            "person.2.fill",
            "person.2.slash",
            "mappin",
            "mappin.and.ellipse",
            "hand.point.up.left",
            "hand.point.up.left.fill",
            "hexagon",
            "hexagon.fill",
            "square.arrowtriangle.4.outward",
            "square.and.arrow.up",
            "photo",
            "photo.fill",
            "trash",
            "document.on.document",
            "square.resize",
            "xmark",
            "checkmark",
            "gear",
            "ellipsis",
            "plus",
            "minus",
            "pencil",
            "folder",
            "list.bullet"
        ]

        // Warm up the cache on background thread to avoid blocking main thread
        Task.detached(priority: .utility) { [weak self] in
            for symbol in commonSymbols {
                _ = await self?.label(for: symbol)
            }
        }
    }

    /// Clear the cache (useful for memory pressure or testing)
    public func clearCache() {
        cache.removeAll()
        preloadCommonSymbols()
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
