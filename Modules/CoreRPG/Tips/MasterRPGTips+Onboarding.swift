// @copyright André Trettin

import SwiftUI
import TipKit

// Split out of MasterRPGTips.swift along its existing MARK boundary. See CODE_AUDIT §9.5.

public struct FirstItemTip: Tip {
    static let itemCreated = Event(id: "onboarding.item-created.v2")

    public var id: String { "onboarding.first-item.v2" }

    public var title: Text {
        Text("Create your first item", bundle: .module)
    }

    public var message: Text? {
        Text(
            "Add an adventure, character, map, or other game resource—or import an existing campaign.",
            bundle: .module
        )
    }

    public var image: Image? {
        Image(systemName: "plus")
    }

    public var actions: [Action] {
        Action(
            id: MasterRPGTips.importCampaignActionID,
            title: String(localized: "Import Campaign", bundle: .module)
        ) {
            MasterRPGTips.requestImportCampaign()
        }
    }

    public var rules: [Rule] {
        #Rule(
            MasterRPGTipState.$forceReplay,
            MasterRPGTipState.$databaseReady,
            MasterRPGTipState.$regularItemCount
        ) { forceReplay, databaseReady, itemCount in
            forceReplay || (databaseReady && itemCount == 0)
        }
        #Rule(MasterRPGTipState.$forceReplay, Self.itemCreated) { forceReplay, event in
            forceReplay || event.donations.count == 0
        }
    }

    public var options: [Option] {
        MaxDisplayCount(3)
    }
}

public struct FirstEntryTip: Tip {
    static let entryCreated = Event(id: "onboarding.entry-created.v1")

    public var id: String { "onboarding.first-entry.v1" }

    public var title: Text {
        Text("Add your first entry", bundle: .module)
    }

    public var message: Text? {
        Text(
            "Entries hold the scenes, notes, values, and details inside an item.",
            bundle: .module
        )
    }

    public var image: Image? {
        Image(systemName: "note.text.badge.plus")
    }

    public var rules: [Rule] {
        #Rule(
            MasterRPGTipState.$forceReplay,
            MasterRPGTipState.$databaseReady,
            MasterRPGTipState.$regularItemCount,
            MasterRPGTipState.$entryCount
        ) { forceReplay, databaseReady, itemCount, entryCount in
            forceReplay || (databaseReady && itemCount > 0 && entryCount == 0)
        }
        #Rule(MasterRPGTipState.$forceReplay, Self.entryCreated) { forceReplay, event in
            forceReplay || event.donations.count == 0
        }
    }

    public var options: [Option] {
        MaxDisplayCount(3)
    }
}

public struct OrganizeContentTip: Tip {
    static let contentOrganized = Event(id: "onboarding.content-organized.v2")

    public var id: String { "onboarding.organize-content.v2" }

    public var title: Text {
        Text("Organize your campaign", bundle: .module)
    }

    public var message: Text? {
        Text(
            "You have several items now. Use folders and collections to keep related content together.",
            bundle: .module
        )
    }

    public var image: Image? {
        Image(systemName: "folder.badge.plus")
    }

    public var rules: [Rule] {
        #Rule(
            MasterRPGTipState.$forceReplay,
            MasterRPGTipState.$databaseReady,
            MasterRPGTipState.$topLevelItemCount,
            MasterRPGTipState.$organizationCount
        ) { forceReplay, databaseReady, itemCount, organizationCount in
            forceReplay || (databaseReady && itemCount >= 4 && organizationCount == 0)
        }
        #Rule(MasterRPGTipState.$forceReplay, Self.contentOrganized) {
            forceReplay,
            event in
            forceReplay || event.donations.count == 0
        }
    }

    public var options: [Option] {
        MaxDisplayCount(3)
    }
}

public struct LinkContentTip: Tip {
    static let contentLinked = Event(id: "onboarding.content-linked.v2")

    public var id: String { "onboarding.link-content.v2" }

    public var title: Text {
        Text("Link related content", bundle: .module)
    }

    public var message: Text? {
        Text(
            "Select a resource, then confirm to connect it with the entry you are editing.",
            bundle: .module
        )
    }

    public var image: Image? {
        Image(systemName: "link")
    }

    public var rules: [Rule] {
        #Rule(
            MasterRPGTipState.$forceReplay,
            MasterRPGTipState.$databaseReady,
            MasterRPGTipState.$regularItemCount,
            MasterRPGTipState.$entryCount,
            MasterRPGTipState.$linkCount
        ) { forceReplay, databaseReady, itemCount, entryCount, linkCount in
            forceReplay
                || (databaseReady && itemCount >= 2 && entryCount > 0 && linkCount == 0)
        }
        #Rule(MasterRPGTipState.$forceReplay, Self.contentLinked) { forceReplay, event in
            forceReplay || event.donations.count == 0
        }
    }

    public var options: [Option] {
        MaxDisplayCount(3)
    }
}
