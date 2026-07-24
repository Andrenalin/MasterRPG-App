// @copyright André Trettin

import SwiftUI
import TipKit

/// Shared, action-driven guidance for the primary MasterRPG workflows.
///
/// Events are donated only after the related operation succeeds, so tips do
/// not advance for cancelled or failed actions.
public enum MasterRPGTips {
    public static let firstItem = FirstItemTip()
    public static let organizeContent = OrganizeContentTip()
    public static let linkContent = LinkContentTip()
    public static let startOrJoinGame = StartOrJoinGameTip()

    /// Configures the persistent TipKit datastore for the current app.
    /// Pass `-reset-tips` while debugging to start from a clean datastore.
    public static func configure() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-reset-tips") {
            try? Tips.resetDatastore()
        }
#endif
        try? Tips.configure()
    }

    /// Restores all tips for the current app, including their event history.
    public static func reset() {
        try? Tips.resetDatastore()
    }

    public static func donateItemCreated() async {
        await FirstItemTip.itemCreated.donate()
    }

    public static func donateContentOrganized() async {
        await OrganizeContentTip.contentOrganized.donate()
    }

    public static func donateContentLinked() async {
        await LinkContentTip.contentLinked.donate()
    }

    public static func donateGameStartedOrJoined() async {
        await StartOrJoinGameTip.gameStartedOrJoined.donate()
    }
}

public struct FirstItemTip: Tip {
    static let itemCreated = Event(id: "item-created")

    public var title: Text {
        Text("Create your first item", bundle: .module)
    }

    public var message: Text? {
        Text("Add an adventure, character, map, or other game resource to begin building your campaign.", bundle: .module)
    }

    public var image: Image? {
        Image(systemName: "plus")
    }

    public var rules: [Rule] {
        #Rule(Self.itemCreated) { $0.donations.count == 0 }
    }
}

public struct OrganizeContentTip: Tip {
    static let contentOrganized = Event(id: "content-organized")

    public var title: Text {
        Text("Organize your campaign", bundle: .module)
    }

    public var message: Text? {
        Text("Use folders and collections to keep related content together.", bundle: .module)
    }

    public var image: Image? {
        Image(systemName: "folder.badge.plus")
    }

    public var rules: [Rule] {
        #Rule(FirstItemTip.itemCreated) { $0.donations.count > 0 }
        #Rule(Self.contentOrganized) { $0.donations.count == 0 }
    }
}

public struct LinkContentTip: Tip {
    static let contentLinked = Event(id: "content-linked")

    public var title: Text {
        Text("Link related content", bundle: .module)
    }

    public var message: Text? {
        Text("Connect characters, maps, media, and tables so they are ready together at the table.", bundle: .module)
    }

    public var image: Image? {
        Image(systemName: "link")
    }

    public var rules: [Rule] {
        #Rule(Self.contentLinked) { $0.donations.count == 0 }
    }
}

public struct StartOrJoinGameTip: Tip {
    static let gameStartedOrJoined = Event(id: "game-started-or-joined")

    public var title: Text {
        Text("Start or join a game", bundle: .module)
    }

    public var message: Text? {
        Text("Launch a game as Game Master, or join one as a player through SharePlay or your local network.", bundle: .module)
    }

    public var image: Image? {
        Image(systemName: "person.2.fill")
    }

    public var rules: [Rule] {
        #Rule(Self.gameStartedOrJoined) { $0.donations.count == 0 }
    }
}
