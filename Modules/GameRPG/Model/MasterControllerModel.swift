// @copyright André Trettin

import  CoreRPG
import Foundation
import os.log

@MainActor @Observable
final class MasterControllerModel: Sendable {
    var messageCounter: Int = 0
    var seenCounter: Int = 0
    var connectIDPlayers: [ConnectionController.ID: UUID] = [:]
    var asProxy = false
    
    func increaseMessageCounter() {
        messageCounter += 1
    }
    
    func add(connectionId: ConnectionController.ID, playerId: UUID) {
        connectIDPlayers[connectionId] = playerId
    }
    
    func reset(seenCounter: Int) {
        self.seenCounter = seenCounter
    }
}
