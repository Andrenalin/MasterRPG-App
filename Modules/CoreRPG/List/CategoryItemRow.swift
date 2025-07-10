// @copyright André Trettin

import SwiftUI

public struct CategoryItemRow<Value: CategoryTextRepresentable>: View {
    public init(category: Value) {
        self.category = category
    }
    
    let category: Value

    public var body: some View {
        Text(category.title)
            .rowColoredTag(backgroundColor: Color.accentColor)
            .foregroundStyle(Color.primary)
    }
}

#Preview {
    CategoryItemRow(category: ItemListCategory.adventure)
}
