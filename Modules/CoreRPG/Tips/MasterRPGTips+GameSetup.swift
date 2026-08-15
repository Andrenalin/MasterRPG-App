// @copyright André Trettin

import SwiftUI
import TipKit

// Split out of MasterRPGTips.swift along its existing MARK boundary. See CODE_AUDIT §9.5.

public struct ChooseAdventureTip: Tip {
    static let adventureSelected = Event(id: "game.adventure-selected.v1")

    public var id: String { "game.choose-adventure.v1" }

    public var title: Text {
        Text("Choose an adventure", bundle: .module)
    }

    public var message: Text? {
        Text("Select the adventure the Game Master will run before starting the game.", bundle: .module)
    }

    public var image: Image? {
        Image(systemName: "wand.and.stars")
    }

    public var rules: [Rule] {
        #Rule(
            MasterRPGTipState.$forceReplay,
            MasterRPGTipState.$databaseReady,
            MasterRPGTipState.$adventureCount,
            MasterRPGTipState.$hasSelectedAdventure
        ) { forceReplay, databaseReady, adventureCount, hasSelection in
            forceReplay || (databaseReady && adventureCount > 0 && hasSelection == false)
        }
        #Rule(MasterRPGTipState.$forceReplay, Self.adventureSelected) {
            forceReplay,
            event in
            forceReplay || event.donations.count == 0
        }
    }

    public var options: [Option] {
        MaxDisplayCount(3)
    }
}

public struct ChooseCharacterTip: Tip {
    static let characterSelected = Event(id: "game.character-selected.v1")

    public var id: String { "game.choose-character.v1" }

    public var title: Text {
        Text("Choose a character", bundle: .module)
    }

    public var message: Text? {
        Text("Select the character you want to play before joining a game.", bundle: .module)
    }

    public var image: Image? {
        Image(systemName: "theatermasks.fill")
    }

    public var rules: [Rule] {
        #Rule(
            MasterRPGTipState.$forceReplay,
            MasterRPGTipState.$databaseReady,
            MasterRPGTipState.$characterCount,
            MasterRPGTipState.$hasSelectedCharacter
        ) { forceReplay, databaseReady, characterCount, hasSelection in
            forceReplay || (databaseReady && characterCount > 0 && hasSelection == false)
        }
        #Rule(MasterRPGTipState.$forceReplay, Self.characterSelected) {
            forceReplay,
            event in
            forceReplay || event.donations.count == 0
        }
    }

    public var options: [Option] {
        MaxDisplayCount(3)
    }
}

public struct StartOrJoinGameTip: Tip {
    static let gameStartedOrJoined = Event(id: "game.started-or-joined.v2")

    public var id: String { "game.start-or-join.v2" }

    public var title: Text {
        Text("Start or join a game", bundle: .module)
    }

    public var message: Text? {
        Text(
            "Start as Game Master, or join through SharePlay or your local network.",
            bundle: .module
        )
    }

    public var image: Image? {
        Image(systemName: "person.2.fill")
    }

    public var rules: [Rule] {
        #Rule(
            MasterRPGTipState.$forceReplay,
            MasterRPGTipState.$hasSelectedAdventure,
            MasterRPGTipState.$hasSelectedCharacter
        ) { forceReplay, hasAdventure, hasCharacter in
            forceReplay || hasAdventure || hasCharacter
        }
        #Rule(MasterRPGTipState.$forceReplay, Self.gameStartedOrJoined) {
            forceReplay,
            event in
            forceReplay || event.donations.count == 0
        }
    }

    public var options: [Option] {
        MaxDisplayCount(3)
    }
}
