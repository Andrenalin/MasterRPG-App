// @copyright André Trettin

import SwiftUI

extension View {
    public func detailInspectorModifier(folderListControllable: any FolderListControllable) -> some View {
        modifier(DetailInspectorViewModifier(folderListController: folderListControllable))
    }
}

struct DetailInspectorViewModifier: ViewModifier {
    let folderListController: any FolderListControllable
    
    func body(content: Content) -> some View {
#if os(macOS)
        @Bindable var model = folderListController.detailInspectorModel
#endif
        
        content
            .environment(folderListController.detailInspectorModel)
#if os(macOS)
            .applyIf(folderListController.detailInspectorModel.canShowInspector) {
                $0.inspectorAll(isPresented: $model.showInspector) {
                    folderListController.detailInspectorModel.currentInspectorView
                }
            }
#endif
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
            withAnimation { folderListController.detailInspectorModel.showInspector.toggle() }
        } label: {
            Label {
                Text("Inspector", bundle: .module)
            } icon: {
                Image(systemName: "scope")
            }
        }
    }
}
