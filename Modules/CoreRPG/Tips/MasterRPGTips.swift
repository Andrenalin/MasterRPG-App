// @copyright André Trettin

import Foundation
import SwiftUI
import TipKit
import os

/// A testable summary of the user data that controls contextual guidance.
///
/// TipKit events remember that a workflow was completed. This snapshot prevents
/// misleading onboarding before an event has ever been donated, such as showing
/// "Create your first item" to someone who imported an existing campaign.
public struct MasterRPGTipEligibilitySnapshot: Equatable, Sendable {
    public init(
        databaseReady: Bool,
        regularItemCount: Int,
        topLevelItemCount: Int,
        entryCount: Int,
        linkCount: Int,
        organizationCount: Int,
        adventureCount: Int,
        characterCount: Int,
        mapCount: Int
    ) {
        self.databaseReady = databaseReady
        self.regularItemCount = regularItemCount
        self.topLevelItemCount = topLevelItemCount
        self.entryCount = entryCount
        self.linkCount = linkCount
        self.organizationCount = organizationCount
        self.adventureCount = adventureCount
        self.characterCount = characterCount
        self.mapCount = mapCount
    }

    public let databaseReady: Bool
    public let regularItemCount: Int
    public let topLevelItemCount: Int
    public let entryCount: Int
    public let linkCount: Int
    public let organizationCount: Int
    public let adventureCount: Int
    public let characterCount: Int
    public let mapCount: Int

    public var shouldShowFirstItem: Bool {
        databaseReady && regularItemCount == 0
    }

    public var shouldShowFirstEntry: Bool {
        databaseReady && regularItemCount > 0 && entryCount == 0
    }

    public var shouldShowOrganization: Bool {
        databaseReady && topLevelItemCount >= 4 && organizationCount == 0
    }

    public var shouldShowLinking: Bool {
        databaseReady && regularItemCount >= 2 && entryCount > 0 && linkCount == 0
    }

    public var shouldShowAdventureSelection: Bool {
        databaseReady && adventureCount > 0
    }

    public var shouldShowCharacterSelection: Bool {
        databaseReady && characterCount > 0
    }

    public var shouldShowMapEditor: Bool {
        databaseReady && mapCount > 0
    }

    public var shouldShowAnotherWindow: Bool {
        databaseReady && regularItemCount > 0
    }
}

/// Persistent TipKit parameters derived from the live database and current UI.
public enum MasterRPGTipState {
    @Parameter static var databaseReady: Bool = false
    @Parameter static var regularItemCount: Int = 0
    @Parameter static var topLevelItemCount: Int = 0
    @Parameter static var entryCount: Int = 0
    @Parameter static var linkCount: Int = 0
    @Parameter static var organizationCount: Int = 0
    @Parameter static var adventureCount: Int = 0
    @Parameter static var characterCount: Int = 0
    @Parameter static var mapCount: Int = 0
    @Parameter static var hasSelectedAdventure: Bool = false
    @Parameter static var hasSelectedCharacter: Bool = false
    @Parameter static var aiAvailable: Bool = false
    /// True once the game screen's empty/setup backdrop has been replaced by
    /// real content (a map), for either the Game Master or a Player.
    @Parameter static var isShowingGameContent: Bool = false

    /// Session-only override used by the production "Show Tips Again" action.
    @Parameter(.transient) static var forceReplay: Bool = false

    @MainActor
    public static func apply(_ snapshot: MasterRPGTipEligibilitySnapshot) {
        databaseReady = snapshot.databaseReady
        regularItemCount = snapshot.regularItemCount
        topLevelItemCount = snapshot.topLevelItemCount
        entryCount = snapshot.entryCount
        linkCount = snapshot.linkCount
        organizationCount = snapshot.organizationCount
        adventureCount = snapshot.adventureCount
        characterCount = snapshot.characterCount
        mapCount = snapshot.mapCount
    }
}

/// Shared, action-driven guidance for the primary MasterRPG workflows.
public enum MasterRPGTips {
    public static let firstItem = FirstItemTip()
    public static let firstEntry = FirstEntryTip()
    public static let organizeContent = OrganizeContentTip()
    public static let linkContent = LinkContentTip()
    public static let chooseAdventure = ChooseAdventureTip()
    public static let chooseCharacter = ChooseCharacterTip()
    public static let startOrJoinGame = StartOrJoinGameTip()
    public static let askAI = AskAITip()
    public static let openMapEditor = OpenMapEditorTip()
    public static let useMapTools = UseMapToolsTip()
    public static let openAnotherWindow = OpenAnotherWindowTip()
    public static let showJoinCode = ShowJoinCodeTip()

    public static let importCampaignActionID = "import-campaign"
    public static let importCampaignRequested = Notification.Name(
        "de.andretrettin.MasterRPG.importCampaignRequested"
    )

    private static var allTips: [any Tip] {
        [
            firstItem,
            firstEntry,
            organizeContent,
            linkContent,
            chooseAdventure,
            chooseCharacter,
            startOrJoinGame,
            askAI,
            openMapEditor,
            useMapTools,
            openAnotherWindow,
            showJoinCode
        ]
    }

    /// Configures TipKit once for the current application process.
    ///
    /// Debug UI and snapshot tests can pass `-disable-tips`. Interactive
    /// development can pass `-reset-tips` to start with a clean datastore.
    public static func configure() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-reset-tips") {
            do {
                try Tips.resetDatastore()
            } catch {
                Logger.tipKit.error(
                    "Unable to reset the TipKit datastore: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
#endif

        do {
            try Tips.configure()
        } catch let error as TipKitError where error == .tipsDatastoreAlreadyConfigured {
            Logger.tipKit.debug("TipKit was already configured for this process")
        } catch {
            Logger.tipKit.error(
                "Unable to configure TipKit: \(error.localizedDescription, privacy: .public)"
            )
        }

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-disable-tips") {
            Tips.hideAllTipsForTesting()
        }
#endif
    }

    /// Makes every tip eligible for another presentation without deleting the
    /// user's event history or relying on TipKit's testing-only show APIs.
    @MainActor
    @discardableResult
    public static func replay() async -> Bool {
        MasterRPGTipState.forceReplay = true
        for tip in allTips {
            await tip.resetEligibility()
        }
        Logger.tipKit.info("Tip guidance was made eligible for replay")
        return true
    }

    /// Reads the real item graph so imported, synchronized, and example data
    /// participate in eligibility even when no local TipKit event was donated.
    @MainActor
    public static func refreshEligibility(
        rootManager: RootManager,
        databaseReady: Bool = true
    ) {
        var visitedDataModels: Set<ObjectIdentifier> = []
        var regularItemCount = 0
        var topLevelItemCount = 0
        var entryCount = 0
        var linkCount = 0
        var organizationCount = 0
        var adventureCount = 0
        var characterCount = 0
        var mapCount = 0

        for module in NetworkModules.allCases {
            guard let root = rootManager.rootModel(for: module) else { continue }
            let dataModel = root.itemControllable.itemDataModel
            guard visitedDataModels.insert(ObjectIdentifier(dataModel)).inserted else { continue }

            for storedModel in dataModel.itemData.values {
                guard let item = storedModel as? any ItemDataAccessable else { continue }
                if item.specialCategory {
                    organizationCount += 1
                    continue
                }

                regularItemCount += 1
                entryCount += item.entries.count
                if item.parentId == nil {
                    topLevelItemCount += 1
                }

                switch module {
                case .adventure:
                    adventureCount += 1
                case .value:
                    characterCount += 1
                case .map:
                    mapCount += 1
                default:
                    break
                }
            }

            if let linkRegisterController = dataModel.linkRegisterController {
                linkCount = max(
                    linkCount,
                    linkRegisterController.model.sourceItems.values.reduce(0) {
                        $0 + $1.count
                    }
                )
            }
        }

        MasterRPGTipState.apply(
            MasterRPGTipEligibilitySnapshot(
                databaseReady: databaseReady,
                regularItemCount: regularItemCount,
                topLevelItemCount: topLevelItemCount,
                entryCount: entryCount,
                linkCount: linkCount,
                organizationCount: organizationCount,
                adventureCount: adventureCount,
                characterCount: characterCount,
                mapCount: mapCount
            )
        )
    }

    @MainActor
    public static func requestImportCampaign() {
        NotificationCenter.default.post(name: importCampaignRequested, object: nil)
    }

    @MainActor
    public static func setSelectedAdventure(_ isSelected: Bool) {
        MasterRPGTipState.hasSelectedAdventure = isSelected
    }

    @MainActor
    public static func setSelectedCharacter(_ isSelected: Bool) {
        MasterRPGTipState.hasSelectedCharacter = isSelected
    }

    @MainActor
    public static func setAIAvailable(_ isAvailable: Bool) {
        MasterRPGTipState.aiAvailable = isAvailable
    }

    /// Call once the game screen's empty/setup backdrop is replaced by real
    /// content, for either role — see `ShowJoinCodeTip`.
    @MainActor
    public static func setGameContentVisible(_ isVisible: Bool) {
        MasterRPGTipState.isShowingGameContent = isVisible
    }

    static func localizedString(
        _ key: String,
        locale: Locale
    ) -> String {
        let languageCode = locale.language.languageCode?.identifier ?? locale.identifier
        guard
            let localizationURL = Bundle.module.url(
                forResource: languageCode,
                withExtension: "lproj"
            ),
            let localizedBundle = Bundle(url: localizationURL)
        else {
            return key
        }
        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    public static func donateItemCreated() async {
        await FirstItemTip.itemCreated.donate()
    }

    public static func donateEntryCreated() async {
        await FirstEntryTip.entryCreated.donate()
    }

    public static func donateContentOrganized() async {
        await OrganizeContentTip.contentOrganized.donate()
    }

    public static func donateContentLinked() async {
        await LinkContentTip.contentLinked.donate()
    }

    public static func donateAdventureSelected() async {
        await ChooseAdventureTip.adventureSelected.donate()
    }

    public static func donateCharacterSelected() async {
        await ChooseCharacterTip.characterSelected.donate()
    }

    public static func donateGameStartedOrJoined() async {
        await StartOrJoinGameTip.gameStartedOrJoined.donate()
    }

    public static func donateAIAccepted() async {
        await AskAITip.generatedContentAccepted.donate()
    }

    public static func donateMapEditorOpened() async {
        await OpenMapEditorTip.mapEditorOpened.donate()
    }

    public static func donateMapToolUsed() async {
        await UseMapToolsTip.mapToolUsed.donate()
    }

    public static func donateWindowOpened() async {
        await OpenAnotherWindowTip.windowOpened.donate()
    }

    public static func donateJoinCodeViewed() async {
        await ShowJoinCodeTip.joinCodeViewed.donate()
    }

    @MainActor
    public static func recordEntryCreated() {
        MasterRPGTipState.entryCount += 1
        Task {
            await donateEntryCreated()
        }
    }

    @MainActor
    public static func recordContentLinked() {
        MasterRPGTipState.linkCount = max(MasterRPGTipState.linkCount, 1)
        Task {
            await donateContentLinked()
        }
    }

    @MainActor
    public static func recordMapEditorOpened() {
        Task {
            await donateMapEditorOpened()
        }
    }

    @MainActor
    public static func recordMapToolUsed() {
        Task {
            await donateMapToolUsed()
        }
    }

    @MainActor
    public static func recordWindowOpened() {
        Task {
            await donateWindowOpened()
        }
    }
}

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
