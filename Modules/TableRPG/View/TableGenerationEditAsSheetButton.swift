// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Round toggle button that opens/closes the outcome's rich sheet editor.
/// Takes the confirm button's old spot directly under the outcome preview
/// once every table is fully decided — the actual Save/Send confirm moves
/// to the bottom of the panel and only appears while this is toggled on
/// (see `TableGenerationPanelView`).
struct TableGenerationEditAsSheetButton: View {
    let model: TableGenerationModel
    let controller: TableGenerationController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creating the session is fast/local — this pause is a deliberate transition beat, not
    /// a wait on any real work. See CODE_AUDIT §9.14.
    private static let transitionBeat: Duration = .seconds(0.5)

    var body: some View {
        HStack {
            Spacer()

            // Same icon in both states — the round button's own `isSelected`
            // styling (a tinted, filled circle vs. a neutral one) is what
            // shows the toggle is on, not a swapped glyph.
            let title = model.isEditingOutcomeSheet
                ? String(localized: "Done", bundle: .module)
                : String(localized: "Edit as Sheet", bundle: .module)
            Button(action: toggle) {
                Label {
                    Text(verbatim: title)
                } icon: {
                    Image(systemName: "square.and.pencil")
                }
                .labelStyle(.iconOnly)
            }
            .selectedRoundButton(
                title: title,
                module: .table,
                isSelected: model.isEditingOutcomeSheet
            )
        }
    }

    private func toggle() {
        if model.isEditingOutcomeSheet {
            withAnimation(reduceMotion ? nil : .smooth) {
                controller.endEditingOutcomeSheet(model: model)
            }
        } else {
            // Creating the session is fast/local — the pause is a
            // deliberate transition beat, not a wait on any real work.
            controller.beginEditingOutcomeSheet(model: model)
            Task {
                try? await Task.sleep(for: Self.transitionBeat)
                // The panel may have closed or the session been dropped during the beat; the flag
                // alone would show the sheet footer without a session. See CODE_AUDIT_26 §5.134.
                guard !Task.isCancelled, model.outcomeEditingSession != nil else { return }
                withAnimation(reduceMotion ? nil : .smooth) {
                    model.isEditingOutcomeSheet = true
                }
            }
        }
    }
}

#Preview("Closed", traits: .mockData) {
    TableGenerationEditAsSheetButton(model: .previewFullyDecided, controller: .preview)
        .padding()
}

#Preview("Open", traits: .mockData) {
    @Previewable @State var model: TableGenerationModel = {
        let model = TableGenerationModel.previewFullyDecided
        model.isEditingOutcomeSheet = true
        return model
    }()
    TableGenerationEditAsSheetButton(model: model, controller: .preview)
        .padding()
}
