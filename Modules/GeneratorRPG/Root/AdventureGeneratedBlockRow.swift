// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AdventureGeneratedBlockRow: View {
    let block: AdventureChatBlockSnapshot
    let isSelected: Bool
    let toggleSelectionAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String {
        block.titleForSheet(index: block.index)
    }

    private var borderColor: Color {
        isSelected ? .green : .secondary.opacity(0.25)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggleSelectionAction) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? .green : .secondary)
                            .accessibilityHidden(true)
                        Text(verbatim: title)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if block.isPending {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel(Text("Generating block", bundle: .module))
                        }
                    }
                    if !block.content.isEmpty {
                        Text(block.content.markDown())
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityValue(
                isSelected
                ? Text("Selected", bundle: .module)
                : Text("Not selected", bundle: .module)
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    AdventureGeneratedBlockRow(
        block: AdventureChatPreviewData.blocks[0],
        isSelected: true,
        toggleSelectionAction: {}
    )
    .padding()
}
