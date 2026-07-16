// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

struct CharacterGenView: View {
    let value: CharacterGenModel
    let level: Int

    var body: some View {
        VStack(alignment: .leading) {
            Text(verbatim: value.name)
                .font(.headline)
                .textSelection(.enabled)
            Text(verbatim: value.information)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            TagItemRow(tags: value.tags)
            ForEach(value.entries.enumerated(), id: \.self.offset) { _, element in
                Text(entryText(name: element.name, content: element.content))
                if let subvalue = element.groupedValues.first {
                    Divider()
                    CharacterGenView(value: subvalue, level: level + 1)
                }
            }
        }
        .padding(.leading, CGFloat(level * 8))
    }

    private func entryText(name: String, content: String) -> AttributedString {
        var emphasizedName = AttributedString(name)
        emphasizedName.inlinePresentationIntent = .stronglyEmphasized
        emphasizedName.append(AttributedString(": \(content)"))
        return emphasizedName
    }
}

#Preview {
    CharacterGenView(
        value: CharacterGenModel(name: "Mira", information: "A careful ruin scout.", tags: ["scout"]),
        level: 0
    )
}
