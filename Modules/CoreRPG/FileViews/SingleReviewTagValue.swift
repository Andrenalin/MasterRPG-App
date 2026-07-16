// @copyright André Trettin

import SwiftUI

struct SingleReviewTagValue: View {
    let tags: [String]

    var body: some View {
        if tags.isEmpty {
            Text("—", bundle: .module)
        } else if tags.count > 4 {
            let half = tags.count / 2

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    TagItemRow(tags: Array(tags[..<half]))
                }
                HStack(spacing: 4) {
                    TagItemRow(tags: Array(tags[half...]))
                }
            }
        } else {
            HStack(spacing: 4) {
                TagItemRow(tags: tags)
            }
        }
    }
}

#Preview { SingleReviewTagValue(tags: ["dungeon", "mystery", "undead"]) }
