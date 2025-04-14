// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation

@Observable
final class LogGameModel: Identifiable {
    init(id: Int, type: RPGMessageType, subType: RPGMessageActionType, module: NetworkModules, itemId: UUID, players: [UUID] = []) {
        self.id = id
        self.type = type
        self.subType = subType
        self.module = module
        self.itemId = itemId
        self.players = players
    }
    
    var id: Int
    var type: RPGMessageType
    var subType: RPGMessageActionType
    var module: NetworkModules
    var itemId: UUID
    var players: [UUID] = []
}
