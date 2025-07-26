// @copyright André Trettin

import Foundation
import SwiftData

@Model
public final class TagDataModel: Identifiable {
    public init(
        id: UUID = UUID(),
        name: String = "",
        module: NetworkModules.RawValue = NetworkModules.none.rawValue
    ) {
        self.id = id
        self.name = name
        self.module = module
    }
    
    public var id: UUID = UUID()
    public var name: String = ""
    public var module: NetworkModules.RawValue = NetworkModules.none.rawValue
}
