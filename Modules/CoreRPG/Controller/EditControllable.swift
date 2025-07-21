// @copyright André Trettin

import Foundation
import SwiftData

public protocol EditControllable {
    associatedtype Model: Identifiable where Model.ID == UUID

    func addNew(modelContext: ModelContext) -> Model
    func delete(model: any Identifiable)
}
