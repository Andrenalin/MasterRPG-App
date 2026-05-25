// @copyright André Trettin

import AdventureRPG
import CoreRPG
import SwiftUI

struct AppExportView: View {
    let appModel: AppModel
        
    var body: some View {
        ExportProgressPanelView(exportController: exportController, showOptions: true) {
            exportController.exportingAll()
        }
        .presentationDetents([.height(160)])
    }
    
    var exportController: ExportControllable {
        appModel.adventureRoot.exportControllable
    }
}

#Preview {
    AppExportView(appModel: .preview)
}
