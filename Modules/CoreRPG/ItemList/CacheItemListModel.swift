// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor @Observable
public final class CacheItemListModel: Sendable {
    public init() {}

    public enum CacheType: String, CaseIterable, Sendable {
        case name
        case description
        case row
        // Note: image and thumbnail cache moved to ImageCacheControllable.observableImageCache
        case image
    }
    
    @ObservationIgnored
    private var itemLinkCache: [CacheKey: LinkHighlightTextModel] = [:]

    /// A struct key: a string built per lookup allocated on every cell's body evaluation.
    /// See CODE_AUDIT_26 §7.44.
    private struct CacheKey: Hashable {
        let cacheType: CacheType
        let itemId: UUID
    }

    private func cacheId(for cacheType: CacheType, itemId: UUID) -> CacheKey {
        CacheKey(cacheType: cacheType, itemId: itemId)
    }
        
    public func itemLink(cacheType: CacheType, itemId: UUID) -> LinkHighlightTextModel? {
        itemLinkCache[cacheId(for: cacheType, itemId: itemId)]
    }

    public func setItemLink(cacheType: CacheType, itemId: UUID, linkModel: LinkHighlightTextModel) {
        itemLinkCache[cacheId(for: cacheType, itemId: itemId)] = linkModel
    }

    public func reset(cacheType: CacheType, itemId: UUID, text: String) {
        itemLinkCache[cacheId(for: cacheType, itemId: itemId)]?.reset(text: text)
    }

    public func reset(search: String) {
        itemLinkCache.forEach { $0.value.reset(highlightedText: search) }
    }
    
    func reset(itemId: UUID) {
        for cacheType in CacheType.allCases {
            itemLinkCache[cacheId(for: cacheType, itemId: itemId)] = nil
        }
    }

    func resetItemLink() {
        itemLinkCache.removeAll()
    }

    public static let preview: CacheItemListModel = CacheItemListModel()
}
