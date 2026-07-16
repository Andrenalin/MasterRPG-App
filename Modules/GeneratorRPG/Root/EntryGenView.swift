// @copyright André Trettin

import FoundationModels
import SwiftUI

struct EntryGenView: View {
    let entry: EntryGenModel.PartiallyGenerated

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                if let title = entry.name {
                    Text(verbatim: title)
                        .contentTransition(.opacity)
                        .font(.largeTitle)
                        .bold()
                }
                if let description = entry.content {
                    Text(verbatim: description)
                        .contentTransition(.opacity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut, value: entry)
    }
}

extension EntryGenView {
    init() {
        self.init(
            entry: try! EntryGenModel.PartiallyGenerated(
                GeneratedContent(
                    json: #"{"name":"Hidden Lever","content":"A rune-marked lever opens the eastern vault."}"#
                )
            )
        )
    }
}

#Preview {
    EntryGenView()
}
