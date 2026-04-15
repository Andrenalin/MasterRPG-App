// @copyright André Trettin

import SwiftUI

extension View {
    public func detailInspectorModifier() -> some View {
        modifier(DetailInspectorViewModifier())
    }
}

struct DetailInspectorViewModifier: ViewModifier {
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel
    @Environment(AppNavigationModel.self) private var appNavigationModel
    @Environment(ItemRootController.self) private var itemRootController
    
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
            withAnimation { itemRootController.navigationModel.showInspector.toggle() }
        } label: {
            Label {
                Text("Inspector", bundle: .module)
            } icon: {
                Image(systemName: "scope")
            }
        }
    }
}
