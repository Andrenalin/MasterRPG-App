// @copyright André Trettin

import Foundation
import SwiftData

public protocol ItemDataModelable: Identifiable, Equatable {
    associatedtype Model: Observable, PersistentModel
    associatedtype ExchangeModel

    static var newItem: Self { get }
    var itemModel: ExchangeModel { get }

    static func model(modelContext: ModelContext?, id: UUID?) -> Self?
    func withTransaction(_ transaction: (ModelContext) -> Void)
}
