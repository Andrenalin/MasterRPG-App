// @copyright André Trettin

import SwiftUI

struct TagDisplayView: View {
    let tags: [String]

    var body: some View {
        if tags.count > 4 {
            TwoLineTagView(tags: tags)
        } else {
            HStack(spacing: 4) {
                TagItemRow(tags: tags)
            }
        }
    }
}

#Preview("Tags") {
    TagDisplayView(tags: ["Dungeon", "Encounter", "Important"])
        .padding()
}
