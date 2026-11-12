// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The share of a Table item row with a generate button in front of it.
struct TableSharingActionView: View, Equatable {
    let itemId: UUID

    @Environment(TableRootModel.self) private var root
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.itemGenerationAction) private var itemGenerationAction

    var body: some View {
        HStack(spacing: 8) {
            if itemGenerationAction.isEnabled, appGameStateModel.isGameRunning {
                Button {
                    itemGenerationAction(itemId)
                } label: {
                    Label { Text("Generate", bundle: .module) } icon: { Image(systemName: "gear") }
                }
                .selectedRoundButton(title: String(localized: "Generate", bundle: .module), module: .table, isSelected: false)
            }

            GameShareView(root: root.rootController, itemId: itemId, usesModuleSharingView: false)
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemId == rhs.itemId
    }
}

#Preview(traits: .mockData) {
    TableSharingActionView(itemId: MockData.previewId)
        .padding()
}
