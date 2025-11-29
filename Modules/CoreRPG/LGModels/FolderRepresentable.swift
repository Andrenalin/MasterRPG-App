// @copyright André Trettin

import SwiftUI

public struct FolderRepresentable: Identifiable {
    public init(id: UUID, name: String) {
        self.id = id
        self.name = name.isEmpty ? String(localized: FolderRepresentable.untitledName).localizedString : name
    }
    
    public var id: UUID
    public var name: String
    
    static private var untitledName: LocalizedStringResource {
        "Untitled"
    }
}

