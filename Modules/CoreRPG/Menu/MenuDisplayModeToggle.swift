// @copyright André Trettin

import SwiftUI

public struct MenuDisplayModeToggle<Add: View>: View {
    public init(listDisplayModel: ListDisplayModel, showSelectionButton: Bool = true, modal: Bool = false, @ViewBuilder add: () -> Add = EmptyView.init) {
        self.listDisplayModel = listDisplayModel
        self.showSelectionButton = showSelectionButton
        self.modal = modal
        self.addViews = add()
    }
    
    let listDisplayModel: ListDisplayModel
    let showSelectionButton: Bool
    let modal: Bool
    let addViews: Add

    public var body: some View {
        if (showSelectionButton || !listDisplayModel.isSelectionMode) && modal == false {
            MenuSelectionButtonView(listDisplayModel: listDisplayModel)
            Divider()
        }

        addViews

        CompactDisplayModeToggle(listDisplayModel: listDisplayModel)
        MediumDisplayModeToggle(listDisplayModel: listDisplayModel)
        RegularDisplayModeToggle(listDisplayModel: listDisplayModel)
        Divider()
        ListModeToggle(listDisplayModel: listDisplayModel)
        FolderModeToggle(listDisplayModel: listDisplayModel)
    }
}

#Preview {
    MenuDisplayModeToggle(listDisplayModel: ListDisplayModel())
}
