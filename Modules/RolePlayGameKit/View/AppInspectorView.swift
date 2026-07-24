// @copyright André Trettin

import CoreRPG
import SwiftUI
import AdventureRPG

struct AppInspectorView: View {
    let module: NetworkModules
    
    @Environment(AppModel.self) private var appModel
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        ModuleInspectorView(rootController: rootController)
    }
    
    var rootController: ItemRootController {
        appModel.itemRootController(for: module) ?? appModel.adventureRoot.rootController
    }
}

#Preview {
    AppInspectorView(module: .adventure)
        .environment(AppModel.preview)
}
