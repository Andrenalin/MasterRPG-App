// @copyright André Trettin

import SwiftUI

struct TagDisplayView: View {
    let tags: [String]
    let category: ItemListCategory
    let collectionCategory: ItemListCategory

    var body: some View {
        if tags.count > 4 {
            TwoLineTagView(tags: tags, category: category, collectionCategory: collectionCategory)
        } else {
            HStack(spacing: 4) {
                TagItemRow(tags: tags)
            }
        }
    }
}

#Preview("Tags") {
    TagDisplayView(tags: ["Dungeon", "Encounter", "Important"], category: .folder, collectionCategory: .folder)
        .padding()
}
