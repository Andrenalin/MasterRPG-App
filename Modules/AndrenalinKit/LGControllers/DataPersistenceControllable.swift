// @copyright André Trettin

import Foundation
import CoreData
import Observation

public protocol DataPersistenceControllable: Sendable {
    func fetch(id: UUID) async throws -> ModelType?
    func delete(id: UUID) async throws
    func replace(id: UUID, with viewModel: any ModelType) async throws
    func save() async throws
}
