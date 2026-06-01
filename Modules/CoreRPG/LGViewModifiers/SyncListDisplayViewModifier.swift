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
            .onChange(of: listControllable.listDisplayModel.displayMode) { //oldValue, newValue in
                displayMode.wrappedValue <=> listControllable.listDisplayModel.displayMode
            }
            .onChange(of: displayMode.wrappedValue, initial: true) { //oldValue, newValue in
                listControllable.listDisplayModel.displayMode <=> displayMode.wrappedValue
            }
            .onChange(of: listControllable.listDisplayModel.listMode) { oldValue, newValue in
                if listMode.wrappedValue != newValue {
                    print("!!! set to \(newValue) on save")
                    listMode.wrappedValue = newValue
                }
            }
            .onChange(of: listMode.wrappedValue, initial: true) { oldValue, newValue in
                if listControllable.listDisplayModel.listMode != newValue {
                    print("!!! set to \(newValue) on controller")
                    listControllable.listDisplayModel.listMode = newValue
                }
            }
    }
}
