// @copyright André Trettin

import SwiftUI
import TipKit

// Split out of MasterRPGTips.swift along its existing MARK boundary. See CODE_AUDIT §9.5.

public struct AskAITip: Tip {
    static let generatedContentAccepted = Event(id: "editor.ai-content-accepted.v1")

    public var id: String { "editor.ask-ai.v1" }

    public var title: Text {
        Text("Ask AI for a starting point", bundle: .module)
    }

    public var message: Text? {
        Text(
            "Describe what you need, review the generated entries, and accept only the ones you want.",
            bundle: .module
        )
    }

    public var image: Image? {
        Image(systemName: "apple.intelligence")
    }

    public var rules: [Rule] {
        #Rule(
            MasterRPGTipState.$forceReplay,
            MasterRPGTipState.$databaseReady,
            MasterRPGTipState.$entryCount,
            MasterRPGTipState.$aiAvailable
        ) { forceReplay, databaseReady, entryCount, aiAvailable in
            forceReplay || (databaseReady && entryCount > 0 && aiAvailable)
        }
        #Rule(MasterRPGTipState.$forceReplay, Self.generatedContentAccepted) {
            forceReplay,
            event in
            forceReplay || event.donations.count == 0
        }
    }

    public var options: [Option] {
        MaxDisplayCount(3)
    }
}

public struct OpenMapEditorTip: Tip {
    static let mapEditorOpened = Event(id: "map.editor-opened.v1")

    public var id: String { "map.open-editor.v1" }

    public var title: Text {
        Text("Turn this image into a playable map", bundle: .module)
    }

    public var message: Text? {
        Text("Open the Map Editor to add rooms, visibility, pins, and encounter details.", bundle: .module)
    }

    public var image: Image? {
        Image(systemName: "mappin.and.ellipse")
    }

    public var rules: [Rule] {
        #Rule(
            MasterRPGTipState.$forceReplay,
            MasterRPGTipState.$databaseReady,
            MasterRPGTipState.$mapCount
        ) { forceReplay, databaseReady, mapCount in
            forceReplay || (databaseReady && mapCount > 0)
        }
        #Rule(MasterRPGTipState.$forceReplay, Self.mapEditorOpened) { forceReplay, event in
            forceReplay || event.donations.count == 0
        }
    }

    public var options: [Option] {
        MaxDisplayCount(3)
    }
}

public struct UseMapToolsTip: Tip {
    static let mapToolUsed = Event(id: "map.tool-used.v1")

    public var id: String { "map.use-tools.v1" }

    public var title: Text {
        Text("Add pins and control visibility", bundle: .module)
    }

    public var message: Text? {
        Text(
            "Place characters on the map and switch display modes to manage what players can see.",
            bundle: .module
        )
    }

    public var image: Image? {
        Image(systemName: "mappin")
    }

    public var rules: [Rule] {
        #Rule(MasterRPGTipState.$forceReplay, OpenMapEditorTip.mapEditorOpened) {
            forceReplay,
            event in
            forceReplay || event.donations.count > 0
        }
        #Rule(MasterRPGTipState.$forceReplay, Self.mapToolUsed) { forceReplay, event in
            forceReplay || event.donations.count == 0
        }
    }

    public var options: [Option] {
        MaxDisplayCount(3)
    }
}
