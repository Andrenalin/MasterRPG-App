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

                // Takes the confirm button's old spot once every table is
                // fully decided — toggles the sheet editor open/closed;
                // the actual Save/Send confirm only appears once inside it.
                if model.isFullyDecided {
                    TableGenerationEditAsSheetButton(model: model, controller: controller)
                }
            }

            Divider()

            if model.isEditingOutcomeSheet, let session = model.outcomeEditingSession {
                outcomeSheetEditor(session: session)
            } else {
                TableGenerationOccurrenceListView(model: model, controller: controller)
            }

            Divider()

            TableGenerationFooterView(
                closeAction: closeAction,
                isEditingOutcomeSheet: model.isEditingOutcomeSheet,
                saveAction: saveAction,
                sendAction: sendAction
            )
        }
        .frame(maxWidth: 760, maxHeight: 820)
        .themedSurface()
        // `.shadow()` must precede `.clipShape()` — applied after, the shadow gets clipped away
        // at the same rect boundary it's meant to extend past and never renders. See CODE_AUDIT §8.1.
        .shadow(radius: 24)
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
#if os(visionOS)
        .glassBackgroundEffect(in: .rect(cornerRadius: 28, style: .continuous))
#else
        .glassEffectAll(.regular, in: .rect(cornerRadius: 28, style: .continuous))
#endif
    }

    private func outcomeSheetEditor(session: SimpleSheetEditingSession) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                SheetRootEditorView(
                    root: session.rootController,
                    sheetRootModel: session.sheetRootModel,
                    headerTitle: String(localized: "Outcome", bundle: .module),
                    linkTypes: EmptyLinkTransferable.self
                )
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
        // `SheetRootEditorView`/`SheetRootView` don't present the entry
        // editor themselves — in the real app that's supplied by the
        // ancestor `ItemDetailContentView`, which this embedding has no
        // equivalent of, so it's added here instead.
        .overlay(alignment: .center) {
            if let rootManager = session.rootController.rootManager {
                EntryEditorView(
                    rootManager: rootManager,
                    editorModel: session.sheetEditorModel,
                    linkTypes: EmptyLinkTransferable.self
                )
            }
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }
}

private struct TableGenerationOccurrenceListView: View {
    let model: TableGenerationModel
    let controller: TableGenerationController

    var body: some View {
        VStack {
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
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
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
