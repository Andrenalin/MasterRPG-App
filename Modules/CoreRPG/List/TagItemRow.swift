// @copyright André Trettin

import SwiftUI

struct TagItemRow: View {
    let tags: [String]

    var body: some View {
        //let _ = Self._printChanges()
        ForEach(tags, id: \.self) { tag in
            Text(tag)
                .rowColoredTag(backgroundColor: Color.accentColor)
                .foregroundStyle(Color.primary)
        }
    }
}
