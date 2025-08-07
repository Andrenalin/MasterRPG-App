// @copyright André Trettin

import SwiftUI

public struct MenuDisplayModeToggle<Add: View>: View {
    public init(listModel: ListModel, showSelectionButton: Bool = true, @ViewBuilder add: () -> Add = EmptyView.init) {
        self.listModel = listModel
        self.showSelectionButton = showSelectionButton
        self.addViews = add()
    }
    
    let listModel: ListModel
    let showSelectionButton: Bool
    let addViews: Add

    public var body: some View {
        if showSelectionButton || !listModel.isSelectionMode {
            MenuSelectionButtonView(listModel: listModel)
            Divider()
        }
        
        addViews
        
        CompactDisplayModeToggle(listModel: listModel)
        MediumDisplayModeToggle(listModel: listModel)
        RegularDisplayModeToggle(listModel: listModel)
        Divider()
        ListModeToggle(listModel: listModel)
        FolderModeToggle(listModel: listModel)
    }
}

struct ListModeToggle: View {
    let listModel: ListModel
    
    var body: some View {
        @Bindable var listModel = listModel
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
    let listModel: ListModel
    
    var body: some View {
        @Bindable var listModel = listModel
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
    let listModel: ListModel
    
    var body: some View {
        @Bindable var listModel = listModel
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
    let listModel: ListModel
    
    var body: some View {
        @Bindable var listModel = listModel
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
    let listModel: ListModel
    
    var body: some View {
        @Bindable var listModel = listModel
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
