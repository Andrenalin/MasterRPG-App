// @copyright André Trettin

import AndrenalinKit
import CoreData
import Foundation
import RoleGameKit
import RPGDie
import WidgetKit

@Observable @MainActor
final class DataBaseLoader {
    static let shared = DataBaseLoader()
    
    init() {
        self.appModel = AppStore.shared
    }
    
    func setup() async {
        guard !hasInitialized else { return }
        let waiter = Task { @MainActor in
            let databaseModel = DataBaseModel(useCloudKit: appModel.settingsModel.useCloudKit, currentActor: .rpgWidget)
            databaseModel.setup()
            
            self.databaseModel = databaseModel
            
            var context = databaseModel.context
            while context == nil {
                try await Task.sleep(for: .milliseconds(50))
                context = databaseModel.context
            }
            guard let context else { return }
            appModel.setupDiceRootModel(context: context)
        }
        let _ = await waiter.result
        hasInitialized = true
        diceRoot = appModel.diceRoot
    }
    
    let appModel: AppStore
    var diceRoot: DiceRoot?
    private var hasInitialized: Bool = false
    private var databaseModel: DataBaseModel?
    
    var useCloudKit: Bool = false
    var cloiudAccount: CloudKitAccountStatus = .notChecked
}
