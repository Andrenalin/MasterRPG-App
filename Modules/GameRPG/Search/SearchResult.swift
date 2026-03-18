// @copyright André Trettin

import CoreRPG
import Foundation

struct SearchResult: Identifiable, Equatable, Hashable {
    let itemId: UUID
    let itemName: String
    let module: NetworkModules
    let category: ItemListCategory
    let entryId: UUID?
    let entryName: String?
    let matchedContent: String?
    let relevanceScore: Int

    var id: String {
        if let entryId {
            return "\(itemId.uuidString)-\(entryId.uuidString)"
        }
        return itemId.uuidString
    }

    static func calculateRelevance(searchText: String, itemName: String, entryName: String?, content: String?, isItemMatch: Bool) -> Int {
        let search = searchText.lowercased()
        var score = 0

        // Item name exact match (highest priority)
        if itemName.lowercased() == search {
            score += 100
        } else if itemName.lowercased().hasPrefix(search) {
            score += 50
        } else if itemName.lowercased().contains(search) {
            score += 25
        }

        // Entry name match (medium priority)
        if let entryName {
            if entryName.lowercased() == search {
                score += 80
            } else if entryName.lowercased().hasPrefix(search) {
                score += 40
            } else if entryName.lowercased().contains(search) {
                score += 20
            }
        }

        // Content match (lower priority)
        if let content {
            if content.lowercased().contains(search) {
                score += 10
            }
        }

        // Boost item matches over entry matches
        if isItemMatch && entryName == nil {
            score += 15
        }

        return score
    }
}
