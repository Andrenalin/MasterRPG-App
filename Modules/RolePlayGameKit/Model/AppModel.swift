// @copyright André Trettin

import CoreRPG
import CoreData
import Observation
import SwiftUI
import os.log

import AdventureRPG
import DiceRPG
import AudioRPG
import GameRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RPGResources
import RuleRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import WeatherRPG

#if !os(tvOS)
import GeneratorRPG
#endif

@MainActor @Observable
public final class AppModel: Sendable {
    @MainActor public static let shared = AppModel()
    
    // App State Models
    @ObservationIgnored public let appGameStateModel: AppGameStateModel
    @ObservationIgnored public let searchBarVisibleModel: SearchBarVisibleModel
    @ObservationIgnored public let scenesManager: ScenesManager
    @ObservationIgnored public let appFocusModel: AppFocusModel

    @ObservationIgnored public var rpgSpotlightIndexer: RpgSpotlightIndexerDelegate?
    @ObservationIgnored private var configuredContext: NSManagedObjectContext?
    @ObservationIgnored public let settingsModel: AppSettingsModel
    
    // Database
    public var coreDataInitModel: CoreDataInitModel?
    /// File handed to the app through Open In; consumed by the Foundry import screen.
    public var pendingVTTImportUrl: URL?
    public var generatedValueEntry: ValueEntryModel?
    public let databaseModel: DataBaseModel
    /// A document URL handed to the app by the system. The import screen owns
    /// the explicit user confirmation before any bytes are read or applied.
    public var pendingImportUrl: URL?
    @ObservationIgnored var pendingImportNavigator: Navigator?
    @ObservationIgnored var pendingVTTImportNavigator: Navigator?
    @ObservationIgnored var securityScopedImportUrl: URL?
    @ObservationIgnored var pendingExternalRoute: PendingExternalRoute?
    @ObservationIgnored var lastExternalRoute: PendingExternalRoute?
    @ObservationIgnored var lastExternalRouteDate = Date.distantPast
    @ObservationIgnored private var saveDeferralTokens: Set<UUID> = []

    var saveIsDeferred: Bool { !saveDeferralTokens.isEmpty }

    /// Set once the launch cleanup ran, so a view appearing again does not run it again.
    @ObservationIgnored var didCleanDatabaseThisLaunch = false
    var isExclusiveDataMutationActive: Bool {
        DataMutationCoordinator.shared.isActive
    }

    @ObservationIgnored let inAppModel = InAppModel()
    public let inAppController: InAppController

    public var supporterTier: SupporterTier {
        inAppModel.supporterTier
    }
    
    // Routing models
    @ObservationIgnored public var gameNavigator: Navigator
    @ObservationIgnored public var editorNavigator: Navigator
    @ObservationIgnored public var searchNavigator: Navigator
    @ObservationIgnored public var settingsNavigator: Navigator

    /// Backwards-compat alias — points at the Game window's navigator.
    @ObservationIgnored public var navigator: Navigator { gameNavigator }

    /// True when the Game window is in compact horizontal layout (iPhone portrait / split). Used by
    /// `WindowRouter` to decide whether routes flatten to top-level `RootRoute`s or thread through the
    /// editors→`ExtendedTabRoute` compound.
    @ObservationIgnored public var isCompactGameWindow: Bool = false

    /// What was open when the window switched between the compact and the regular layout. Set on
    /// the size class change, consumed by `restoreRouteAfterLayoutChange` once the new layout has
    /// settled; `TabRootView` runs a task keyed on it.
    var layoutRestoreTarget: LayoutRestoreTarget?

    public static let defaultEditorModule: RootRoute = .pdfs

    var selectedModule: RootRoute? = .game
    var selectedEditorModule: RootRoute? = AppModel.defaultEditorModule
    var selectedExtendedModule: ExtendedTabRoute? = nil
    var menuSelectedModule: NetworkModules = .game
    
    public var appNavigationModel: AppNavigationModel
    
    // Module roots
    @ObservationIgnored public let adventureRoot: AdventureRootModel
    @ObservationIgnored public let audioRoot: AudioRootModel
    @ObservationIgnored public let diceRoot: DiceRootModel
    @ObservationIgnored public let gameRoot: GameRoot
    @ObservationIgnored public let mapRoot: MapRootModel
    @ObservationIgnored public let pdfRoot: PdfRootModel
    @ObservationIgnored public let photoRoot: PhotoRootModel
    @ObservationIgnored public let ruleRoot: RuleRootModel
    @ObservationIgnored public let spaceRoot: SpaceRootModel
    @ObservationIgnored public let tableRoot: TableRootModel
    @ObservationIgnored public let characterRoot: CharacterRootModel
    @ObservationIgnored public let weatherRoot: WeatherRootModel
    
#if !os(tvOS)
    @ObservationIgnored public let generatorRoot: GeneratorRootModel
#endif
    
    @ObservationIgnored let tagController: TagController

    let root: RootManager
    
    @MainActor public convenience init() {
        self.init(databaseModelOverride: nil, settingsModelOverride: nil)
    }

    @MainActor private init(
        databaseModelOverride: DataBaseModel?,
        settingsModelOverride: AppSettingsModel?
    ) {
        let gameStateModel = AppGameStateModel()
        self.appGameStateModel = gameStateModel
        self.searchBarVisibleModel = SearchBarVisibleModel()
        self.scenesManager = ScenesManager()
        self.appFocusModel = AppFocusModel()
        self.settingsModel = settingsModelOverride ?? AppSettingsModel()
        
        self.inAppController = InAppController(model: inAppModel)
        
        self.gameNavigator = Self.makeNavigator()
        self.editorNavigator = Self.makeNavigator()
        self.searchNavigator = Self.makeNavigator()
        self.settingsNavigator = Self.makeNavigator()
        
        self.appNavigationModel = AppNavigationModel(appGameStateModel: gameStateModel)
        
        let tagController = TagController()
        self.tagController = tagController
        
#if !os(tvOS)
        let generatorRoot = GeneratorRootFactory.rootModel(tagController: tagController)
        self.generatorRoot = generatorRoot
#endif
        
        let diceRoot = DiceFactory.root(tagController: tagController)
        let photoRoot = PhotoFactory.root(tagController: tagController)
        let audioRoot = AudioFactory.root(tagController: tagController)
        let pdfRoot = PdfFactory.root(tagController: tagController)
        let ruleRoot = RuleFactory.root(tagController: tagController)
        let spaceRoot = SpaceFactory.root(tagController: tagController)
        
#if os(tvOS)
        let tableRoot = TableFactory.root(tagController: tagController, diceRoot: diceRoot, pdfRoot: pdfRoot)
#else
        let tableRoot = TableFactory.root(tagController: tagController, diceRoot: diceRoot, generatorRoot: generatorRoot, pdfRoot: pdfRoot)
#endif
        let weatherRoot = WeatherFactory.root(tagController: tagController, photoRoot: photoRoot)

#if os(tvOS)
        let characterRoot = CharacterRootFactory.root(tagController: tagController, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
#else
        let characterRoot = CharacterRootFactory.root(tagController: tagController, diceRoot: diceRoot, generatorRoot: generatorRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
#endif

#if os(tvOS)
        let mapRoot = MapRootFactory.root(tagController: tagController, audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, characterRoot: characterRoot, weatherRoot: weatherRoot)
#else
        let mapRoot = MapRootFactory.root(tagController: tagController, audioRoot: audioRoot, diceRoot: diceRoot, generatorRoot: generatorRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, characterRoot: characterRoot, weatherRoot: weatherRoot)
#endif

#if os(tvOS)
        let adventureRoot = AdventureFactory.root(tagController: tagController, audioRoot: audioRoot, diceRoot: diceRoot, generatorRoot: nil, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, ruleRoot: ruleRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, characterRoot: characterRoot, weatherRoot: weatherRoot)
#else
        let adventureRoot = AdventureFactory.root(tagController: tagController, audioRoot: audioRoot, diceRoot: diceRoot, generatorRoot: generatorRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, ruleRoot: ruleRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, characterRoot: characterRoot, weatherRoot: weatherRoot)
#endif
        let gameRoot = GameRoot(adventureRoot: adventureRoot, audioRoot: audioRoot, diceRoot: diceRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, ruleRoot: ruleRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, characterRoot: characterRoot, weatherRoot: weatherRoot)
        
        self.adventureRoot = adventureRoot
        self.audioRoot = audioRoot
        self.diceRoot = diceRoot
        self.gameRoot = gameRoot
        self.mapRoot = mapRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.ruleRoot = ruleRoot
        self.spaceRoot = spaceRoot
        self.tableRoot = tableRoot
        self.characterRoot = characterRoot
        self.weatherRoot = weatherRoot
        
#if os(tvOS)
        self.databaseModel = databaseModelOverride ?? DataBaseModel(useCloudKit: false, currentActor: .mainApp)
        root = RootManager(
            adventureRoot: adventureRoot,
            audioRoot: audioRoot,
            characterRoot: characterRoot,
            diceRoot: diceRoot,
            generatorRoot: adventureRoot,
            mapRoot: mapRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            ruleRoot: ruleRoot,
            spaceRoot: spaceRoot,
            tableRoot: tableRoot,
            weatherRoot: weatherRoot
        )
        
#else
        self.databaseModel = databaseModelOverride ?? DataBaseModel(useCloudKit: settingsModel.useCloudKit, currentActor: .mainApp)
        root = RootManager(
            adventureRoot: adventureRoot,
            audioRoot: audioRoot,
            characterRoot: characterRoot,
            diceRoot: diceRoot,
            generatorRoot: generatorRoot,
            mapRoot: mapRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            ruleRoot: ruleRoot,
            spaceRoot: spaceRoot,
            tableRoot: tableRoot,
            weatherRoot: weatherRoot
        )
#endif        

#if !os(tvOS)
        connectIntentsAndWidgets()
#endif
    }
    
    /// How long a navigator waits between the steps of a multi-step route.
    static let navigatorExecutionDelay: TimeInterval = 0.4

    /// The one configuration of the game, editor, search and settings navigators.
    /// See CODE_AUDIT_29 §9.5.
    static func makeNavigator() -> Navigator {
        Navigator(
            configuration: NavigationConfiguration(
                logger: AppModel.navigatorLogger(event:),
                executionDelay: navigatorExecutionDelay,
                verbosity: AppModel.navigatorVerbosity,
                autoDestinationMode: true
            )
        )
    }

    /// Navigation events describe destinations and routes, which can carry the names of items.
    /// They are logged in debug builds only, and never as public text, so a release build writes
    /// none of it to the unified log. See CODE_AUDIT_26 §6.11.
    static var navigatorVerbosity: NavigationEvent.Verbosity {
#if DEBUG
        .info
#else
        .none
#endif
    }

    static func navigatorLogger(event: NavigationEvent) -> Void {
#if DEBUG
        Logger.bootStrap.info("\(event.description, privacy: .private)")
#endif
    }
}
 
/// How a Reset Data request ended.
public enum DataResetOutcome: Sendable, Equatable {
    case completed
    /// Another import, repair or reset holds the data-mutation token; nothing was changed.
    case busy
}

// MARK: - Maintenance

extension AppModel {
    /// Defers opportunistic saves without allowing one overlapping operation to clear another's
    /// deferral. The owner must return the token with `endSaveDeferral(_:)`.
    @discardableResult
    func beginSaveDeferral() -> UUID {
        let token = UUID()
        saveDeferralTokens.insert(token)
        return token
    }

    func endSaveDeferral(_ token: UUID) {
        saveDeferralTokens.remove(token)
    }

    /// Grants exclusive access to mutate the shared controller graph. Import and repair operations
    /// must retain the returned token until their final consolidated save has completed.
    func beginExclusiveDataMutation() -> UUID? {
        DataMutationCoordinator.shared.begin()
    }

    func endExclusiveDataMutation(_ token: UUID) {
        DataMutationCoordinator.shared.end(token)
    }

    /// Compatibility spelling retained for the Foundry import transaction.
    func beginExternalImport() -> UUID? {
        beginExclusiveDataMutation()
    }

    /// Compatibility spelling retained for the Foundry import transaction.
    func endExternalImport(_ token: UUID) {
        endExclusiveDataMutation(token)
    }

    /// Clears the database. Takes the exclusive data-mutation token and defers saves like import and
    /// repair do, so a reset cannot interleave with a bulk writer's in-memory graph and final save.
    /// The files themselves are not deleted. See CODE_AUDIT_26 §5.41.
    @discardableResult
    public func resetData() async -> DataResetOutcome {
        guard let mutationToken = beginExclusiveDataMutation() else { return .busy }
        let saveDeferral = beginSaveDeferral()
        await adventureRoot.resetData()
        endSaveDeferral(saveDeferral)
        await save()
        endExclusiveDataMutation(mutationToken)
        return .completed
    }
    
    public func save() async {
        guard saveIsDeferred == false else { return }
        // Before `setupRootModels` ran (app sent to the background while the database is still
        // loading, or the store failed to open) the module roots have no link register or data
        // controller yet, and there is nothing to save. Reading the link register then trips
        // the `ItemControllable.linkRegisterController` precondition.
        guard configuredContext != nil else { return }
        await adventureRoot.save()
    }

    /// How long the store is given, after the last save, for the work Core Data starts behind it.
    static let persistenceSettleDelay: Duration = .seconds(10)

    /// Returns once the work Core Data does behind a save has had time to finish: the WAL
    /// checkpoint it schedules, the Spotlight index update and the CloudKit export. All of them
    /// take the SQLite lock of the store, which lies in the App Group container, and RunningBoard
    /// kills an app that is suspended while it holds a lock there (`0xdead10cc`, seen on Vision
    /// Pro mid-game). Meant to run inside a background task after `save()`.
    ///
    /// None of that work reports when it is done, so this drains the coordinator's queue and then
    /// waits `persistenceSettleDelay`. It narrows the window; it does not close it.
    public func waitForPersistenceToSettle() async {
        guard let coordinator = coreDataInitModel?.container?.persistentStoreCoordinator else { return }
        await coordinator.perform {}
        try? await Task.sleep(for: Self.persistenceSettleDelay)
    }

    /// Removes hidden items and leftovers once per launch. Holds the data-mutation token, and is
    /// skipped (to be retried by the next appearance) while an import, repair or reset is
    /// running. See CODE_AUDIT_26 §5.123.
    public func cleanDatabase() async {
        guard !didCleanDatabaseThisLaunch,
              let mutationToken = beginExclusiveDataMutation()
        else { return }
        didCleanDatabaseThisLaunch = true
        defer { endExclusiveDataMutation(mutationToken) }
        for step in moduleFolderRepairSteps {
            await step.root.itemDataCleanup()
            // Files a game of the previous run left behind. See CODE_AUDIT_21 §5.14.
            await step.root.itemControllable.removeLeftoverGameFiles()
        }
    }

    /// Imports the bundled example data and returns once it is saved. Holds the data-mutation
    /// lock and defers opportunistic saves like the file import does, and throws when the
    /// import fails, so the caller reports the real result instead of assuming success.
    /// See CODE_AUDIT_Folder §3.7.
    public func installExampleData(isGerman: Bool = false) async throws {
        let bundle = RPGResources.Resources.bundle
        let name = isGerman ? RPGResources.Resources.exampleFirstGermanData : RPGResources.Resources.exampleFirstData
        guard let url = bundle.url(forResource: name, withExtension: "gmz") else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard let mutationToken = beginExclusiveDataMutation() else {
            throw ExampleDataInstallError.dataMutationActive
        }
        let saveDeferral = beginSaveDeferral()
        let result = await adventureRoot.importControllable.importUrl(from: url).result
        endSaveDeferral(saveDeferral)
        await save()
        endExclusiveDataMutation(mutationToken)
        try result.get()
        refreshTipEligibility()
    }

}

// MARK: ExampleUrlProvider

extension AppModel: ExampleUrlProvider {
    public func urlExampleData(isGerman: Bool) -> URL? {
        let bundle = RPGResources.Resources.bundle
        let name = isGerman ? RPGResources.Resources.exampleFirstGermanData : RPGResources.Resources.exampleFirstData
        guard let url = bundle.url(forResource: name, withExtension: "gmz") else { return nil }
        return url
    }
}

// MARK: - DB and Root Models setup

extension AppModel {
    @MainActor public func setupRootModels(context: NSManagedObjectContext, spotlightIndexer: RpgSpotlightIndexerDelegate?, coreDataInitModel: CoreDataInitModel?) {
        // The scene's `.task(id: context)` and a background intent's readiness gate can both
        // reach this for the same context.
        guard configuredContext !== context else { return }
        configuredContext = context
        tagController.setup(context: context)
        adventureRoot.setUp(root: root, context: context)
        gameRoot.setUpStatistics(context: context)

        self.rpgSpotlightIndexer = spotlightIndexer
        spotlightIndexer?.observeIndexing()
        
        self.coreDataInitModel = coreDataInitModel

        self.appNavigationModel.initialRouteType = .ready
        DatabaseReadiness.markReady()
        presentPendingExternalNavigationIfNeeded()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.tipEligibilityRefreshDelay)
            self?.refreshTipEligibility()
        }
    }

    /// Starts the database and root models without a scene, for background App Intents. The
    /// scene's iCloud-account alert is skipped: CloudKit copes with a missing account itself.
    /// See CODE_AUDIT_16 §5.3.
    @MainActor public func startDatabaseForBackgroundWork() {
        if databaseModel.context == nil {
            databaseModel.setup()
        }
        guard let context = databaseModel.context else { return }
        setupRootModels(
            context: context,
            spotlightIndexer: databaseModel.spotlightIndexer,
            coreDataInitModel: databaseModel.coreDataInitModel
        )
    }

    /// Gives the just-`.ready` route a moment to finish settling before the first tip
    /// eligibility check, rather than racing it. See CODE_AUDIT §9.14.
    static let tipEligibilityRefreshDelay: Duration = .milliseconds(500)
}

extension AppModel {
    @MainActor public static var preview: AppModel {
        let dbModel = DataBaseModel.preview
        let model = AppModel(
            databaseModelOverride: dbModel,
            settingsModelOverride: .previewFixture()
        )
        model.setupRootModels(context: dbModel.context.unsafelyUnwrapped, spotlightIndexer: nil, coreDataInitModel: nil)
        return model
    }
    @MainActor public static var previewWithoutDatabase: AppModel {
        let model = AppModel(
            databaseModelOverride: DataBaseModel.previewWithOutSetup(),
            settingsModelOverride: .previewFixture()
        )
        model.selectedExtendedModule = .maps
        return model
    }
}

/// Why the example data could not be installed.
public enum ExampleDataInstallError: LocalizedError {
    /// Another import or repair is changing the RPG data.
    case dataMutationActive

    public var errorDescription: String? {
        switch self {
        case .dataMutationActive:
            String(localized: "Another import or repair operation is currently changing RPG data. Try again when it finishes.", bundle: .module)
        }
    }
}
