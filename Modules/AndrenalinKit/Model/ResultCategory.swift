// @copyright André Trettin

import Foundation
import SwiftUI

public extension EnvironmentValues {
    var resultCategory: ResultCategory? {
        get { self[ResultCategoryKey.self] }
        set { self[ResultCategoryKey.self] = newValue }
    }
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

struct ResultCategoryKey: EnvironmentKey {
    static let defaultValue: ResultCategory? = nil
}
