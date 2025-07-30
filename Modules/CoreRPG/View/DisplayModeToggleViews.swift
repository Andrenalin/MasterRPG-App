// @copyright André Trettin

import SwiftUI

public struct MenuDisplayModeToggle: View {
    public init(listModel: ListModel, showSelectionButton: Bool = true) {
        self.listModel = listModel
        self.showSelectionButton = showSelectionButton
    }
    
    let listModel: ListModel
    let showSelectionButton: Bool

    public var body: some View {
        if showSelectionButton || !listModel.isSelectionMode {
            MenuSelectionButtonView(listModel: listModel)
            Divider()
        }

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
                Text("All", bundle: .module)
            } icon: {
                Image(systemName: "list.bullet")
            }
        }
        .keyboardShortcut("A", modifiers: [.command, .shift])
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
        .keyboardShortcut("F", modifiers: [.command, .shift])
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
        .keyboardShortcut("C", modifiers: [.command, .shift])
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
        .keyboardShortcut("M", modifiers: [.command, .shift])
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
        .keyboardShortcut("R", modifiers: [.command, .shift])
    }
}
