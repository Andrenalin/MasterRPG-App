// @copyright André Trettin

import SwiftUI

@MainActor @Observable public final class AppNavigationModel {
    public init(selectedItemId: UUID? = nil, selectedEntryId: UUID? = nil) {
        self.selectedItemId = selectedItemId
        self.selectedEntryId = selectedEntryId
    }
    
    public var selectedItemId: UUID?
    public var selectedEntryId: UUID?
}
