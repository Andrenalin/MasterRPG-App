// @copyright André Trettin

import Foundation
import SwiftUI

public struct TagFilterSelection: Equatable, Hashable, Sendable {
    public init(tag: String, state: TagFilterSelection.Status = .inactive) {
        self.tag = tag
        self.state = state
    }

    public enum Status: Equatable, Hashable, Sendable {
        case selected
        case deselected
        case inactive
    }

    public let tag: String
    public let state: Status

    func select(for tags: [String]) -> Bool {
        switch state {
        case .selected:
            return tags.contains { $0.localizedUppercase == tag.localizedUppercase }
        case .deselected:
            return !tags.contains { $0.localizedUppercase == tag.localizedUppercase }
        case .inactive:
            return true
        }
    }

    public static func filter(for tags: [String], with filters: [TagFilterSelection], exclude: String) -> Bool {
        var result = true
        for filter in filters {
            if filter.tag == exclude {
                continue
            }
            result = result && filter.select(for: tags)
            if !result {
                break
            }
        }
        return result
    }

    public static func isHidden(tag: String, isHidden: Bool, with filters: [TagFilterSelection]) -> Bool {
        isHidden && filters.contains(where: { $0.tag == tag })
    }

    public static func isHidden(tag: String, with filters: [TagFilterSelection]) -> Bool {
        filters.contains(where: { $0.tag == tag })
    }
}
