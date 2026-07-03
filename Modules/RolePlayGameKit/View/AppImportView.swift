// @copyright André Trettin

import AdventureRPG
import CoreRPG
import SwiftUI

struct AppImportView: View {
    let appModel: AppModel
        
    var body: some View {
        ImportProgressPanelView(rootManager: appModel.root, urlProvider: appModel, importController: importController) { value in
            appModel.saveIsDeferred = value
        }
    }
    
    var importController: ImportControllable {
        appModel.adventureRoot.importControllable
    }
}

#Preview {
    AppImportView(appModel: .preview)
}
