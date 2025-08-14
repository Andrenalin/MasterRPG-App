// @copyright André Trettin

import SwiftUI

public struct MenuDisplayModeToggle<Add: View>: View {
    public init(listModel: ListModel, listDisplayModel: ListDisplayModel, showSelectionButton: Bool = true, @ViewBuilder add: () -> Add = EmptyView.init) {
        self.listModel = listModel
        self.listDisplayModel = listDisplayModel
        self.showSelectionButton = showSelectionButton
        self.addViews = add()
    }
    
    let listModel: ListModel
    let listDisplayModel: ListDisplayModel
    let showSelectionButton: Bool
    let addViews: Add

    public var body: some View {
        if showSelectionButton || !listModel.isSelectionMode {
            MenuSelectionButtonView(listModel: listModel)
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
        @Bindable var listModel = listDisplayModel
        Toggle(isOn: $listModel.isListMode) {
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
        @Bindable var listModel = listDisplayModel
        Toggle(isOn: $listModel.isFolderMode) {
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
        @Bindable var listModel = listDisplayModel
        Toggle(isOn: $listModel.isCompactDisplayMode) {
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
        @Bindable var listModel = listDisplayModel
        Toggle(isOn: $listModel.isMediumDisplayMode) {
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
        @Bindable var listModel = listDisplayModel
        Toggle(isOn: $listModel.isRegularDisplayMode) {
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
