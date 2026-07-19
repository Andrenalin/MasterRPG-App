// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation

@testable import GameRPG

extension GameNetworkModel {
    /// Test builder in the legacy config/roster/control shape: derives
    /// sender/masterState the same way production senders do, so existing test
    /// scenarios stay expressed in the familiar form.
    init(
        version: Int = GameNetworkModel.currentVersion,
        counter: Int,
        proxyCounter: Int,
        type: RPGMessageType,
        subType: RPGMessageActionType,
        gameConfig: GameConfigModel,
        gameRoster: GameRosterModel = .empty,
        gameControl: GameControlModel = .empty,
        audience: GameMessageAudience = .automatic,
        purpose: GameMessagePurpose = .event,
        data: NetworkCodableDataType
    ) {
        let identity = GameNetworkModel.legacyIdentity(
            config: gameConfig,
            players: gameRoster.players,
            controls: gameControl.controls,
            features: gameControl.features
        )
        self.init(
            version: version,
            counter: counter,
            proxyCounter: proxyCounter,
            type: type,
            subType: subType,
            masterId: identity.masterId,
            sender: identity.sender,
            masterState: identity.masterState,
            audience: audience,
            purpose: purpose,
            data: data
        )
    }
}
#endif
