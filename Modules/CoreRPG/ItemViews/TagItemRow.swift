// @copyright André Trettin

import SwiftUI

#Preview {
    List {
        TagItemRow(tags: ["Dungeon", "Encounter", "Important"])
    }
}

public struct TagItemRow: View {
    public init(tags: [String]) {
        self.tags = tags
    }

    let tags: [String]

    public var body: some View {
        ForEach(tags, id: \.self) { tag in
            Text(tag)
                .rowColoredTag(backgroundColor: Color.accentColor)
                .foregroundStyle(Color.primary)
        }
    }
}
