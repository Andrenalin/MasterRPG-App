// @copyright André Trettin

import SwiftUI

struct TwoLineTagView: View {
    let tags: [String]

    var body: some View {
        let half = tags.count / 2

        VStack(alignment: .leading, spacing: 4) {
            if half > 0 {
                HStack(spacing: 4) {
                    // Only tags: a category chip here showed "Entry" for items with more than four
                    // tags and for no other item, and the detail view has no such chip.
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
    TwoLineTagView(tags: ["Dungeon", "Encounter", "Important", "Combat", "Boss"])
        .padding()
}
