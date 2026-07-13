// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview {
    SettingsRouteDestinationView(route: .validate)
        .environment(AppModel())
}

enum SettingsRoute {
    case exportData
    case importData
    case validate
}

extension SettingsRoute: NavigationDestination {
    var body: some View {
        SettingsRouteDestinationView(route: self)
    }
}

struct SettingsRouteDestinationView: View {
    let route: SettingsRoute
    
    @Environment(AppModel.self) private var appModel
    
    var body: some View {
        switch route {
        case .exportData:
            AppExportView(appModel: appModel)
        case .importData:
            AppImportView(appModel: appModel)
        case .validate:
            ValidateRepairView(controller: ValidateRepairController(appModel: appModel, model: ValidateRepairModel()))
        }
    }
}
