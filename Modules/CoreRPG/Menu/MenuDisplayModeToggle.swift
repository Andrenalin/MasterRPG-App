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

struct ListModeToggle: View {
    let listDisplayModel: ListDisplayModel
    
    var body: some View {
        @Bindable var listDisplayModel = listDisplayModel
        Toggle(isOn: $listDisplayModel.isListMode) {
            Label {
                Text("List", bundle: .module)
            } icon: {
                Image(systemName: "list.bullet")
            }
        }
#if !os(tvOS)
        .keyboardShortcut("L", modifiers: [.command, .shift])
#endif
    }
}

struct FolderModeToggle: View {
    let listDisplayModel: ListDisplayModel
    
    var body: some View {
        @Bindable var listDisplayModel = listDisplayModel
        Toggle(isOn: $listDisplayModel.isFolderMode) {
            Label {
                Text("Folder", bundle: .module)
            } icon: {
                Image(systemName: "folder")
            }
        }
#if !os(tvOS)
        .keyboardShortcut("F", modifiers: [.command, .shift])
#endif
    }
}

struct CompactDisplayModeToggle: View {
    let listDisplayModel: ListDisplayModel
    
    var body: some View {
        @Bindable var listDisplayModel = listDisplayModel
        Toggle(isOn: $listDisplayModel.isCompactDisplayMode) {
            Label {
                Text("Compact", bundle: .module)
            } icon: {
                Image(systemName: "list.dash.header.rectangle")
            }
        }
#if !os(tvOS)
        .keyboardShortcut("C", modifiers: [.command, .shift])
#endif
    }
}

struct MediumDisplayModeToggle: View {
    let listDisplayModel: ListDisplayModel
    
    var body: some View {
        @Bindable var listDisplayModel = listDisplayModel
        Toggle(isOn: $listDisplayModel.isMediumDisplayMode) {
            Label {
                Text("Medium", bundle: .module)
            } icon: {
                Image(systemName: "list.bullet.rectangle")
            }
        }
#if !os(tvOS)
        .keyboardShortcut("M", modifiers: [.command, .shift])
#endif
    }
}

struct RegularDisplayModeToggle: View {
    let listDisplayModel: ListDisplayModel
    
    var body: some View {
        @Bindable var listDisplayModel = listDisplayModel
        Toggle(isOn: $listDisplayModel.isRegularDisplayMode) {
            Label {
                Text("Regular", bundle: .module)
            } icon: {
                Image(systemName: "list.bullet.below.rectangle")
            }
        }
#if !os(tvOS)
        .keyboardShortcut("R", modifiers: [.command, .shift])
#endif
    }
}

#Preview {
    MenuDisplayModeToggle(listDisplayModel: ListDisplayModel())
}

#Preview { ListModeToggle(listDisplayModel: ListDisplayModel()) }
#Preview { FolderModeToggle(listDisplayModel: ListDisplayModel()) }
#Preview { CompactDisplayModeToggle(listDisplayModel: ListDisplayModel()) }
#Preview { MediumDisplayModeToggle(listDisplayModel: ListDisplayModel()) }
#Preview { RegularDisplayModeToggle(listDisplayModel: ListDisplayModel()) }
