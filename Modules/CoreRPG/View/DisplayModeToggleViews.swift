// @copyright André Trettin

import SwiftUI

public struct MenuDisplayModeToggle: View {
    public init(listModel: ListModel) {
        self.listModel = listModel
    }
    
    let listModel: ListModel

    public var body: some View {
        CompactDisplayModeToggle(listModel: listModel)
        MediumDisplayModeToggle(listModel: listModel)
        RegularDisplayModeToggle(listModel: listModel)
    }
}

public struct CompactDisplayModeToggle: View {
    public init(listModel: ListModel) {
        self.listModel = listModel
    }
    
    let listModel: ListModel
    
    public var body: some View {
        @Bindable var listModel = listModel
        Toggle(isOn: $listModel.isCompactDisplayMode) {
            Label {
                Text("Compact", bundle: .module)
            } icon: {
                Image(systemName: "list.dash.header.rectangle")
            }
        }
    }
}

struct MediumDisplayModeToggle: View {
    public init(listModel: ListModel) {
        self.listModel = listModel
    }

    let listModel: ListModel
    
    public var body: some View {
        @Bindable var listModel = listModel
        Toggle(isOn: $listModel.isMediumDisplayMode) {
            Label {
                Text("Medium", bundle: .module)
            } icon: {
                Image(systemName: "list.bullet.rectangle")
            }
        }
    }
}

public struct RegularDisplayModeToggle: View {
    public init(listModel: ListModel) {
        self.listModel = listModel
    }
    let listModel: ListModel
    
    public var body: some View {
        @Bindable var listModel = listModel
        Toggle(isOn: $listModel.isRegularDisplayMode) {
            Label {
                Text("Regular", bundle: .module)
            } icon: {
                Image(systemName: "list.bullet.below.rectangle")
            }
        }
    }
}
