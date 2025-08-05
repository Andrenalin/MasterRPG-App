// @copyright André Trettin

import SwiftUI

@Observable
public final class GroupItemSelectionModel {
    public init(selectedItem: UUID? = nil) {
        self.selectedItem = selectedItem
    }

    public var selectedItem: UUID?
}
