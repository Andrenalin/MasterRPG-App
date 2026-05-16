// @copyright André Trettin

import SwiftUI

extension View {
    public func detailInspectorModifier(root: any ItemRootControllable) -> some View {
        modifier(DetailInspectorViewModifier(root: root))
    }
}

struct DetailInspectorViewModifier: ViewModifier {
    let root: any ItemRootControllable
    
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel
    @Environment(AppNavigationModel.self) private var appNavigationModel
    
    func body(content: Content) -> some View {
        content
            .toolbar {
                if appNavigationModel.canShowInspector(appSizeModel: appWindowSizeModel) {
                    ToolbarItemGroup(placement: .secondaryActionAll) {
                        inspectorButton
                    }
                }
            }
    }
    
    var inspectorButton: some View {
        Button {
            withAnimation { root.navigationModel.showInspector.toggle() }
        } label: {
            Label {
                Text("Inspector", bundle: .module)
            } icon: {
                Image(systemName: "scope")
            }
        }
    }
}
