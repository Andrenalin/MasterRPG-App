// @copyright André Trettin

import AdventureRPG
import CoreRPG
import SwiftUI

struct AppImportView: View {
    let appModel: AppModel
        
    var body: some View {
        ExportProgressPanelView(exportController: exportController) {
            let exportIds = exportController.exportingAll()
            return exportController.export(ids: exportIds)
        }
        .presentationDetents([.height(160)])
    }
    
    var exportController: ExportControllable {
        appModel.adventureRoot.exportControllable
    }
}

#Preview {
    AppImportView(appModel: .preview)
}
