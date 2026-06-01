// @copyright André Trettin

import SwiftUI

public extension View {
    func syncListDisplay(listControllable: any FolderListControllable, displayMode: Binding<ListDisplayModel.DisplayMode>, listMode: Binding<ListDisplayModel.ListMode>) -> some View {
        modifier(SyncListDisplayViewModifier(listControllable: listControllable, displayMode: displayMode, listMode: listMode))
    }
}

struct SyncListDisplayViewModifier: ViewModifier {
    let listControllable: any FolderListControllable
    let displayMode: Binding<ListDisplayModel.DisplayMode>
    let listMode: Binding<ListDisplayModel.ListMode>

    func body(content: Content) -> some View {
        content
            .onChange(of: listControllable.listDisplayModel.displayMode) {
                displayMode.wrappedValue <=> listControllable.listDisplayModel.displayMode
            }
            .onChange(of: listControllable.listDisplayModel.listMode) { oldValue, newValue in
                listMode.wrappedValue <=> newValue
            }
            .onAppear {
                if listControllable.listDisplayModel.listMode != listMode.wrappedValue {
                    listControllable.listDisplayModel.listMode = listMode.wrappedValue
                }
                if listControllable.listDisplayModel.displayMode != displayMode.wrappedValue {
                    listControllable.listDisplayModel.displayMode = displayMode.wrappedValue
                }
            }
    }
}
