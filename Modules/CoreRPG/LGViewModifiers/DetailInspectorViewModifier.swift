// @copyright André Trettin

import SwiftUI

extension View {
    public func detailInspectorModifier(folderListControllable: any FolderListControllable) -> some View {
        modifier(DetailInspectorViewModifier(folderListController: folderListControllable))
    }
}

struct DetailInspectorViewModifier: ViewModifier {
    let folderListController: any FolderListControllable

    @State private var showInspector: Bool = false
    
    func body(content: Content) -> some View {
        content
            .environment(folderListController.detailInspectorModel)
            .applyIf(folderListController.detailInspectorModel.canShowInspector) {
                $0.inspectorAll(isPresented: $showInspector) {
                    folderListController.detailInspectorModel.currentInspectorView
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .secondaryActionAll) {
                    if folderListController.detailInspectorModel.canShowInspector {
                        inspectorButton
                    }
                }
            }
    }
    
    var inspectorButton: some View {
        Button {
            withAnimation { showInspector.toggle() }
        } label: {
            Label {
                Text("Inspector", bundle: .module)
            } icon: {
                Image(systemName: "scope")
            }
        }
    }
}
