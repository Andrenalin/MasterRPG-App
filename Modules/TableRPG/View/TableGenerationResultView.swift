// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableGenerationResultView: View {
    let model: TableGenerationModel

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(theme.tint(for: .table))

            VStack(alignment: .leading) {
                Text("Outcome", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let outcome = model.currentOutcome {
                    Text(outcome)
                        .bold()
                } else {
                    Text(
                        "Choose or roll every table to see the outcome.",
                        bundle: .module
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.tint(for: .table).opacity(model.currentOutcome == nil ? 0.08 : 0.18),
            in: .rect(cornerRadius: 20, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview("Choose or roll a table", traits: .mockData) {
    TableGenerationResultView(model: .preview)
        .padding()
}

#Preview("Nested outcome", traits: .mockData) {
    TableGenerationResultView(model: .previewNested)
        .padding()
}
