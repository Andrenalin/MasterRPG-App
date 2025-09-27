// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
#if os(macOS)
internal import AppKit
#else
internal import UIKit
#endif

@MainActor @Observable
final class PlayerControllerModel: Sendable {
    var gameUpdateType: NetworkModules = .none
    var messageCounter: Int = 0
    var responseCounter: Int = 0
    var lostMaster: Bool = true
    var hasSendPlayer = false
    var asGameMaster = false
    
    var gameModelMessage = GameModelMessage()

    func increaseMessageCounter() {
        messageCounter += 1
    }

    func reset(lostMaster: Bool) {
        self.lostMaster = lostMaster
    }
    
    func reset(sendPlayer: Bool) {
        self.hasSendPlayer = sendPlayer
    }
    
    func setGameUpdateType(_ type: NetworkModules) {
        gameUpdateType = type
    }
}

actor GameModelMessage {
    private var messages: [GameNetworkModel] = []
    private var processing: Bool = false
    
    func append(_ message: GameNetworkModel) {
        messages.append(message)
    }
    
    func next() -> GameNetworkModel? {
        guard !processing && !messages.isEmpty else { return nil }
        processing = true
        return messages.removeFirst()
    }
    
    func processed() {
        processing = false
    }
}
