// @copyright André Trettin

import SwiftUI
import TipKit

// Split out of MasterRPGTips.swift along its existing MARK boundary. See CODE_AUDIT §9.5.

/// Points at the wifi icon once the game screen shows real content, telling
/// the Game Master or a Player they can tap it to see their join code.
public struct ShowJoinCodeTip: Tip {
    static let joinCodeViewed = Event(id: "game.join-code-viewed.v1")

    public var id: String { "game.show-join-code.v1" }

    public var title: Text {
        Text("See your join code", bundle: .module)
    }

    public var message: Text? {
        Text("Tap here anytime to see the code others need to join your game.", bundle: .module)
    }

    public var image: Image? {
        Image(systemName: "wifi")
    }

    public var rules: [Rule] {
        #Rule(
            MasterRPGTipState.$forceReplay,
            MasterRPGTipState.$isShowingGameContent
        ) { forceReplay, isShowingGameContent in
            forceReplay || isShowingGameContent
        }
        #Rule(MasterRPGTipState.$forceReplay, Self.joinCodeViewed) { forceReplay, event in
            forceReplay || event.donations.count == 0
        }
    }

    public var options: [Option] {
        MaxDisplayCount(3)
    }
}

public struct OpenAnotherWindowTip: Tip {
    static let windowOpened = Event(id: "navigation.secondary-window-opened.v1")

    public var id: String { "navigation.open-another-window.v1" }

    public var title: Text {
        Text("Keep another workspace open", bundle: .module)
    }

    public var message: Text? {
        Text(
            "Open the Game or Editor in another window while keeping your current workspace visible.",
            bundle: .module
        )
    }

    public var image: Image? {
        Image(systemName: "macwindow.on.rectangle")
    }

    public var rules: [Rule] {
        #Rule(
            MasterRPGTipState.$forceReplay,
            MasterRPGTipState.$databaseReady,
            MasterRPGTipState.$regularItemCount
        ) { forceReplay, databaseReady, itemCount in
            forceReplay || (databaseReady && itemCount > 0)
        }
        #Rule(MasterRPGTipState.$forceReplay, Self.windowOpened) { forceReplay, event in
            forceReplay || event.donations.count == 0
        }
    }

    public var options: [Option] {
        MaxDisplayCount(3)
    }
}
