// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableGenerationPanelView: View {
    let model: TableGenerationModel
    let controller: TableGenerationController
    let closeAction: () -> Void
    let saveAction: () -> Void
    let sendAction: (UUID?) -> Void

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

                // Only offered once every table is fully decided — that's
                // exactly when the outcome becomes an editable TextEditor.
                if model.isFullyDecided {
                    TableGenerationSaveSendButton(
                        saveAction: saveAction,
                        sendAction: sendAction
                    )
                }
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

            TableGenerationFooterView(closeAction: closeAction)
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
        closeAction: {},
        saveAction: {},
        sendAction: { _ in }
    )
    .padding()
}

#Preview("Nested generation", traits: .mockData) {
    @Previewable @State var model = TableGenerationModel.previewNested
    TableGenerationPanelView(
        model: model,
        controller: .preview,
        closeAction: {},
        saveAction: {},
        sendAction: { _ in }
    )
    .padding()
}

#Preview("Empty table", traits: .mockData) {
    @Previewable @State var model = TableGenerationModel.previewEmpty
    TableGenerationPanelView(
        model: model,
        controller: .preview,
        closeAction: {},
        saveAction: {},
        sendAction: { _ in }
    )
    .padding()
}

#Preview("Fully decided — editable outcome", traits: .mockData) {
    @Previewable @State var model = TableGenerationModel.previewFullyDecided
    TableGenerationPanelView(
        model: model,
        controller: .preview,
        closeAction: {},
        saveAction: {},
        sendAction: { _ in }
    )
    .padding()
}
