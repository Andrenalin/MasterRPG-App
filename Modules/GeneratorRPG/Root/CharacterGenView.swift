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
            // `CharacterEntryGenModel` is a `@Generable` FoundationModels schema
            // type — adding a client-generated `id` would make it part of what
            // the model is expected to produce, so identity is keyed on the
            // entry's own `Hashable` content instead of its (unstable, once the
            // AI-streamed list is edited or reordered) position.
            ForEach(value.entries, id: \.self) { element in
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
