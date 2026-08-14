// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Bottom toolbar row: Close on the leading edge always; the outcome's
/// Save/Send confirm button on the trailing edge, but only while the sheet
/// editor is open — editing is the finalization step, so confirming is only
/// offered there, right alongside cancel.
struct TableGenerationFooterView: View {
    let closeAction: () -> Void
    let isEditingOutcomeSheet: Bool
    let saveAction: () -> Void
    let sendAction: (UUID?) -> Void

    var body: some View {
        HStack {
            Button(action: closeAction) {
                Image(systemName: "xmark")
            }
            .selectedRoundButton(
                title: String(localized: "Close", bundle: .module),
                module: .table,
                isSelected: false
            )

            Spacer()

            if isEditingOutcomeSheet {
                TableGenerationSaveSendButton(
                    saveAction: saveAction,
                    sendAction: sendAction
                )
            }
        }
        .padding()
    }
}

#Preview("Selection") {
    TableGenerationFooterView(
        closeAction: {},
        isEditingOutcomeSheet: false,
        saveAction: {},
        sendAction: { _ in }
    )
}

#Preview("Editing — confirm shown", traits: .mockData) {
    TableGenerationFooterView(
        closeAction: {},
        isEditingOutcomeSheet: true,
        saveAction: {},
        sendAction: { _ in }
    )
}
