// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor @Observable
public final class CacheItemListModel: Sendable {
    public init() {}

    public enum CacheType: String, CaseIterable, Sendable {
        case name
        case description
        case entryName
        case content
        case row
        case image
        case thumbnail
    }
    
    private static var imageCache: [String: AKImage] = [:]

    public func imageCache(cacheType: CacheType, itemId: UUID) -> AKImage? {
        CacheItemListModel.imageCache[cacheId(for: cacheType, itemId: itemId)]
    }

    public func setImageCache(cacheType: CacheType, itemId: UUID, image: AKImage?) {
        CacheItemListModel.imageCache[cacheId(for: cacheType, itemId: itemId)] = image
    }
    
    public func resetImageCache(itemId: UUID, includeImage: Bool = true) {
        if includeImage {
            setImageCache(cacheType: .image, itemId: itemId, image: nil)
        }
        setImageCache(cacheType: .thumbnail, itemId: itemId, image: nil)
    }

    @ObservationIgnored
    private var itemLinkCache: [String: LinkHighlightTextModel] = [:]
    
    private func cacheId(for cacheType: CacheType, itemId: UUID) -> String {
        "\(cacheType.rawValue)-\(itemId)"
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

public final class CacheItemList {
    public init() {}
    
    var cache: [UUID: CacheItemListModel] = [:]
    
    @MainActor
    public func itemCache(for itemId: UUID) -> CacheItemListModel {
        guard let model = cache[itemId] else {
            let model = CacheItemListModel()
            cache[itemId] = model
            return model
        }
        return model
    }
    
    @MainActor
    func reset(search: String) {
        cache.values.forEach { $0.reset(search: search) }
    }

}
