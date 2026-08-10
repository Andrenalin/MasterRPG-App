// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableGenerationPanelView: View {
    let model: TableGenerationModel
    let controller: TableGenerationController
    let cancelAction: () -> Void
    let confirmAction: () -> Void

    var body: some View {
        VStack {
            TableGenerationHeaderView(
                model: model,
                controller: controller
            )

            // Hidden until the first choice is made, to give the occurrence
            // list more room before there is anything to preview.
            if model.currentOutcome != nil {
                TableGenerationResultView(model: model)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading) {
                    TableGenerationOccurrenceView(
                        model: model,
                        occurrence: model.root,
                        controller: controller
                    )
                }
            }
            .scrollIndicators(.hidden)

            if let errorMessage = model.errorMessage {
                Label {
                    Text(errorMessage)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
                .padding(.horizontal)
            }

            Divider()

            TableGenerationFooterView(
                canConfirm: model.canConfirm,
                cancelAction: cancelAction,
                confirmAction: confirmAction
            )
        }
        .frame(maxWidth: 760, maxHeight: 820)
        .themedSurface()
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
#if os(visionOS)
        .glassBackgroundEffect(in: .rect(cornerRadius: 28, style: .continuous))
#else
        .glassEffectAll(.regular, in: .rect(cornerRadius: 28, style: .continuous))
#endif
        .shadow(radius: 24)
    }
}

#Preview("Dice table", traits: .mockData) {
    @Previewable @State var model = TableGenerationModel.preview
    TableGenerationPanelView(
        model: model,
        controller: .preview,
        cancelAction: {},
        confirmAction: {}
    )
    .padding()
}

#Preview("Nested generation", traits: .mockData) {
    @Previewable @State var model = TableGenerationModel.previewNested
    TableGenerationPanelView(
        model: model,
        controller: .preview,
        cancelAction: {},
        confirmAction: {}
    )
    .padding()
}

#Preview("Empty table", traits: .mockData) {
    @Previewable @State var model = TableGenerationModel.previewEmpty
    TableGenerationPanelView(
        model: model,
        controller: .preview,
        cancelAction: {},
        confirmAction: {}
    )
    .padding()
}

#Preview("Fully decided — editable outcome", traits: .mockData) {
    @Previewable @State var model = TableGenerationModel.previewFullyDecided
    TableGenerationPanelView(
        model: model,
        controller: .preview,
        cancelAction: {},
        confirmAction: {}
    )
    .padding()
}
