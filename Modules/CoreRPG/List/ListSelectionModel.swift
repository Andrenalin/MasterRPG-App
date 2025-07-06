// @copyright André Trettin

import SwiftUI

@Observable
public final class ListSelectionModel<Value> {
    public init(selectedItem: Value? = nil) {
        self.selectedItem = selectedItem
    }
    
    public var selectedItem: Value?
}
