// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableGenerationEntryRow: View {
    init(
        entry: TableGenerationEntry,
        occurrence: TableGenerationOccurrence,
        model: TableGenerationModel,
        controller: TableGenerationController
    ) {
        self.entry = entry
        self.occurrence = occurrence
        self.model = model
        self.controller = controller
        _contentModel = State(
            initialValue: LinkHighlightTextModel(
                linkControllable: nil,
                text: entry.content
            )
        )
    }

    let entry: TableGenerationEntry
    let occurrence: TableGenerationOccurrence
    let model: TableGenerationModel
    let controller: TableGenerationController

    @State private var contentModel: LinkHighlightTextModel
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth) {
                    controller.select(
                        entryId: entry.id,
                        in: occurrence,
                        model: model
                    )
                }
            } label: {
                HStack(alignment: .top) {
                    Image(
                        systemName: isSelected
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .foregroundStyle(
                        isSelected
                            ? theme.tint(for: .table)
                            : .secondary
                    )

                    VStack(alignment: .leading) {
                        Text(entry.name.withoutLink())
                            .bold()
                        if !entry.content.isEmpty {
                            LinkHighlightTextView(
                                model: contentModel,
                                allowsLinkInteraction: false
                            )
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(
                isSelected
                    ? Text("Selected", bundle: .module)
                    : Text("Not selected", bundle: .module)
            )
            .accessibilityHint(selectionHint)

            if occurrence.allowsMultipleSelection, !isSelected {
                GlassButton {
                    withAnimation(reduceMotion ? nil : .smooth) {
                        controller.hide(
                            entryId: entry.id,
                            in: occurrence,
                            model: model
                        )
                    }
                } label: {
                    Label {
                        Text("Hide", bundle: .module)
                    } icon: {
                        Image(systemName: "eye.slash")
                    }
                    .labelStyle(.iconOnly)
                }
                .disabled(
                    !controller.canHide(
                        entryId: entry.id,
                        in: occurrence
                    )
                )
                .accessibilityHint(
                    Text(
                        "Exclude this entry from the generated result",
                        bundle: .module
                    )
                )
            }
        }
        .padding()
        .background(
            theme.tint(for: .table).opacity(isSelected ? 0.16 : 0.05),
            in: .rect(cornerRadius: TableGenerationLayout.cardRadius, style: .continuous)
        )
        .onChange(of: entry.content) { _, newContent in
            contentModel.reset(text: newContent)
        }
    }

    private var isSelected: Bool {
        occurrence.selectedEntryIds.contains(entry.id)
    }

    private var selectionHint: Text {
        if isSelected {
            if occurrence.allowsMultipleSelection {
                Text("Deselect this generated result", bundle: .module)
            } else {
                Text("Deselect to show the other entries", bundle: .module)
            }
        } else {
            Text("Select this generated result", bundle: .module)
        }
    }
}

#Preview("Not selected", traits: .mockData) {
    @Previewable @State var model = TableGenerationModel.preview
    TableGenerationEntryRow(
        entry: model.root.entries[0],
        occurrence: model.root,
        model: model,
        controller: .preview
    )
    .padding()
}

#Preview("Selected", traits: .mockData) {
    @Previewable @State var model = TableGenerationModel.previewResolved
    TableGenerationEntryRow(
        entry: model.root.entries[0],
        occurrence: model.root,
        model: model,
        controller: .preview
    )
    .padding()
}

#Preview("Multi-select, hideable", traits: .mockData) {
    @Previewable @State var model = TableGenerationModel.previewList
    TableGenerationEntryRow(
        entry: model.root.entries[0],
        occurrence: model.root,
        model: model,
        controller: .preview
    )
    .padding()
}
