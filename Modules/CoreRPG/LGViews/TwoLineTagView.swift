// @copyright André Trettin

import SwiftUI

struct TwoLineTagView: View {
    let tags: [String]
    let category: ItemListCategory
    let collectionCategory: ItemListCategory

    var body: some View {
        let half = tags.count / 2

        VStack(alignment: .leading, spacing: 4) {
            if half > 0 {
                HStack(spacing: 4) {
                    if category != .folder && category != collectionCategory {
                        CategoryItemRow(category: category)
                    }
                    TagItemRow(tags: Array(tags[0..<half]))
                }
            }

            if half < tags.count {
                HStack(spacing: 4) {
                    TagItemRow(tags: Array(tags[half...]))
                }
            }
        }
    }
}

#Preview("Many tags") {
    TwoLineTagView(tags: ["Dungeon", "Encounter", "Important", "Combat", "Boss"], category: .folder, collectionCategory: .folder)
        .padding()
}
