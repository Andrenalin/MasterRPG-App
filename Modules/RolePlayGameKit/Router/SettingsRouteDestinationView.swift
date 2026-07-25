// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SettingsRouteDestinationView: View {
    let route: SettingsRoute

    @Environment(AppModel.self) private var appModel

    var body: some View {
        switch route {
        case .exportData:
            AppExportView(appModel: appModel)
        case .importData:
            AppImportView(appModel: appModel)
        case .supporter:
            InAppView(inAppController: appModel.inAppController)
        case .validate:
            ValidateRepairView(controller: ValidateRepairController(appModel: appModel, model: ValidateRepairModel()))
        }
    }
}

#Preview("Validate database destination") {
    SettingsRouteDestinationView(route: .validate)
        .environment(AppModel())
}
