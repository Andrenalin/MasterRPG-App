// @copyright André Trettin

import AdventureRPG
import CoreRPG
import SwiftUI

struct AppImportView: View {
    let appModel: AppModel
        
    var body: some View {
        ImportProgressPanelView(urlProvider: appModel, importController: importController)
    }
    
    var importController: ImportControllable {
        appModel.adventureRoot.importControllable
    }
}

#Preview {
    AppImportView(appModel: .preview)
}
