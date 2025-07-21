// @copyright André Trettin

import SwiftUI

public struct TagItemRow: View {
    public init(tags: [String]) {
        self.tags = tags
    }

    let tags: [String]

    public var body: some View {
        let _ = Self._printChanges()
        ForEach(tags, id: \.self) { tag in
            Text(tag)
                .rowColoredTag(backgroundColor: Color.accentColor)
                .foregroundStyle(Color.primary)
        }
    }
}
