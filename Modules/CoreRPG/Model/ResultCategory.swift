// @copyright André Trettin

import Foundation
import SwiftUI

public extension EnvironmentValues {
    @Entry var resultCategory: ResultCategory? = nil
}

public struct ResultCategory: Equatable, Hashable, Codable, Sendable {
    public let id: UUID
    public let childId: UUID?
    public let module: NetworkModules

    public init(id: UUID, childId: UUID? = nil, module: NetworkModules) {
        self.id = id
        self.childId = childId
        self.module = module
    }
}
