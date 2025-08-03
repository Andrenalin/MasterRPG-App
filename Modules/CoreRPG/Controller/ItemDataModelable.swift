// @copyright André Trettin

import Foundation
import SwiftData

public protocol ItemDataModelable: Identifiable, Equatable {
    associatedtype Model: Observable, PersistentModel
    associatedtype ExchangeModel
    
    static func model(modelContext: ModelContext?, id: UUID?) -> Self?
    var itemModel: ExchangeModel { get }
    static var newItem: Self { get }
}
