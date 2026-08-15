// @copyright André Trettin

import Foundation
import SwiftUI
import TipKit
import os

// MARK: - Eligibility Snapshot

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

// Onboarding/Game Setup/Feature Discovery/Sharing & Window tip structs moved to
// MasterRPGTips+Onboarding.swift / +GameSetup.swift / +FeatureDiscovery.swift / +Sharing.swift
// — see CODE_AUDIT §9.5.
