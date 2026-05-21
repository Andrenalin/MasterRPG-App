// @copyright André Trettin

import CoreRPG
import SwiftUI
import AdventureRPG

struct AppInspectorView: View {
    let isExtendedRoutes: Bool
    
    @Environment(AppModel.self) private var appModel
    
    var body: some View {
        let _ = Self._printChanges()
        ModuleInspectorView(rootController: rootController)
    }
    
    var rootController: ItemRootController {
        appModel.itemRootController(for: selectedModule) ?? appModel.adventureRoot.rootController
    }
    
    var selectedModule: NetworkModules {
        isExtendedRoutes ? (appModel.selectedEditorModule ?? AppModel.defaultEditorModule).module : (appModel.selectedModule ?? .game).module
    }
}

#Preview {
    AppInspectorView(isExtendedRoutes: false)
}
