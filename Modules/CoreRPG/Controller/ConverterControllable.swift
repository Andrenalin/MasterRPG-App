// @copyright André Trettin

import Foundation
import SwiftData
import SwiftUI

public protocol ConverterControllable: Sendable {
}

public extension ConverterControllable {
    static func convert(category: ItemListCategory, tags: [String], module: NetworkModules, collection: ItemListCategory) -> (ItemListCategory, [String]) {
        if category == .folder || category == collection {
            return (category, tags)
        }
        return (.item, [category.title] + tags)
    }
}
