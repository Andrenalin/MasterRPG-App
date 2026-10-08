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

    @ObservationIgnored public let optionKeyDownModel: OptionKeyDownModel
    @ObservationIgnored public var rpgSpotlightIndexer: RpgSpotlightIndexerDelegate?
    @ObservationIgnored private var configuredContext: NSManagedObjectContext?
    @ObservationIgnored public let settingsModel: AppSettingsModel
    
    // Database
    public var coreDataInitModel: CoreDataInitModel?
    /// File handed to the app through Open In; consumed by the Foundry import screen.
    public var pendingVTTImportURL: URL?
    public var generatedValueEntry: ValueEntryModel?
#if os(tvOS)
    public let databaseModel: DataBaseModel
#else
    public let databaseModel: DataBaseModel
#endif
    /// A document URL handed to the app by the system. The import screen owns
    /// the explicit user confirmation before any bytes are read or applied.
    public var pendingImportURL: URL?
    @ObservationIgnored private var pendingImportNavigator: Navigator?
    @ObservationIgnored private var pendingVTTImportNavigator: Navigator?
    @ObservationIgnored private var securityScopedImportURL: URL?
    @ObservationIgnored private var pendingExternalRoute: PendingExternalRoute?
    @ObservationIgnored private var lastExternalRoute: PendingExternalRoute?
    @ObservationIgnored private var lastExternalRouteDate = Date.distantPast
    @ObservationIgnored private var saveDeferralTokens: Set<UUID> = []

    var saveIsDeferred: Bool { !saveDeferralTokens.isEmpty }
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
        self.optionKeyDownModel = OptionKeyDownModel()
        self.settingsModel = settingsModelOverride ?? AppSettingsModel()
        
        self.inAppController = InAppController(model: inAppModel)
        
        self.gameNavigator = Navigator(
            configuration: NavigationConfiguration(
                restorationKey: "game.1.0.14",
                logger: AppModel.navigatorLogger(event:),
                executionDelay: 0.4,
                verbosity: .info,
                autoDestinationMode: true
            )
        )
        self.editorNavigator = Navigator(
            configuration: NavigationConfiguration(
                restorationKey: "editor.1.0.14",
                logger: AppModel.navigatorLogger(event:),
                executionDelay: 0.4,
                verbosity: .info,
                autoDestinationMode: true
            )
        )
        self.searchNavigator = Navigator(
            configuration: NavigationConfiguration(
                restorationKey: "search.1.0.14",
                logger: AppModel.navigatorLogger(event:),
                executionDelay: 0.4,
                verbosity: .info,
                autoDestinationMode: true
            )
        )
        self.settingsNavigator = Navigator(
            configuration: NavigationConfiguration(
                restorationKey: "settings.1.0.13",
                logger: AppModel.navigatorLogger(event:),
                executionDelay: 0.4,
                verbosity: .info,
                autoDestinationMode: true
            )
        )
        
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
        let mapRoot = MapRootFactory.root(tagController: tagController, audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, characterRoot: characterRoot)
#else
        let mapRoot = MapRootFactory.root(tagController: tagController, audioRoot: audioRoot, diceRoot: diceRoot, generatorRoot: generatorRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, characterRoot: characterRoot)
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
        let characterDataModel = characterRoot.itemControllable.itemDataModel
        characterDataModel.contentWidgetPublisher = { [weak characterDataModel] in
            guard let characterDataModel else { return }
            ContentWidgetSnapshot.publish(module: .value, from: characterDataModel)
        }

        let adventureDataModel = adventureRoot.itemControllable.itemDataModel
        adventureDataModel.contentWidgetPublisher = { [weak adventureDataModel] in
            guard let adventureDataModel else { return }
            ContentWidgetSnapshot.publish(module: .adventure, from: adventureDataModel)
        }
#endif
    }
    
    static func navigatorLogger(event: NavigationEvent) -> Void {
        Logger.bootStrap.info("\(event.description, privacy: .public)")
    }
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

    public func resetData() async {
        await adventureRoot.resetData()
    }
    
    public func save() async {
        guard saveIsDeferred == false else { return }
        await adventureRoot.save()
    }
    
    public func cleanDatabase() async {
        for step in moduleFolderRepairSteps {
            try? await step.root.itemDataCleanup()
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

    public func windowPlacement(for module: NetworkModules) -> WindowPlacementPosition {
        switch module {
        case .none, .setting, .editor, .game, .generator, .search:
                return .leading(SceneId.game.rawValue)
            case .photo:
                if appGameStateModel.gameModus == .player {
                    return .leading(SceneId.game.rawValue, fallback: nil)
                }
                return
                    .above(NetworkModules.adventure.linkWindowId, fallback: SceneId.game.rawValue)
            case .map:
                return .trailing(NetworkModules.adventure.linkWindowId, fallback: SceneId.game.rawValue)
            case .table:
                return .leading(SceneId.game.rawValue)
            case .adventure:
                return .trailing(SceneId.game.rawValue)
            case .dice:
                if appGameStateModel.gameModus == .player {
                    return .trailing(NetworkModules.value.linkWindowId, fallback: SceneId.game.rawValue)
                }
                return .below(NetworkModules.table.linkWindowId, fallback: SceneId.game.rawValue)
            case .weather:
                return .above(NetworkModules.map.linkWindowId, fallback: SceneId.game.rawValue)
            case .value:
                if appGameStateModel.gameModus == .player {
                    return .trailing(SceneId.game.rawValue, fallback: nil)
                }
                return .above(NetworkModules.table.linkWindowId, fallback: SceneId.game.rawValue)

            case .audio:
                if appGameStateModel.gameModus == .player {
                    return .leading(NetworkModules.photo.linkWindowId, fallback: SceneId.game.rawValue)
                }
                return .below(NetworkModules.adventure.linkWindowId, fallback: SceneId.game.rawValue)
            case .pdf:
                return .leading(NetworkModules.table.linkWindowId, fallback: SceneId.game.rawValue)
            case .rule:
                return .trailing(NetworkModules.pdf.linkWindowId, fallback: SceneId.game.rawValue)
            case .space:
                if appGameStateModel.gameModus == .player {
                    return .leading(NetworkModules.photo.linkWindowId, fallback: SceneId.game.rawValue)
                }
                return .below(NetworkModules.map.linkWindowId, fallback: SceneId.game.rawValue)
        @unknown default:
            return .leading(SceneId.game.rawValue)
        }
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

// MARK: - Routing

extension AppModel {
    @MainActor public func presentImport(_ url: URL, with navigator: Navigator) {
        guard pendingImportURL != url else { return }
        securityScopedImportURL?.stopAccessingSecurityScopedResource()
        securityScopedImportURL = url.startAccessingSecurityScopedResource() ? url : nil
        pendingImportURL = url
        guard appNavigationModel.initialRouteType == .ready else {
            pendingImportNavigator = navigator
            return
        }
        navigator.navigate(to: SettingsRoute.importData, method: .managedCover)
    }

    @MainActor public func presentVTTImport(_ url: URL, with navigator: Navigator) {
        guard pendingVTTImportURL != url else { return }
        pendingVTTImportURL = url
        guard appNavigationModel.initialRouteType == .ready else {
            pendingVTTImportNavigator = navigator
            return
        }
        presentVTTImport(with: navigator)
    }

    @MainActor public func finishImportPresentation() {
        securityScopedImportURL?.stopAccessingSecurityScopedResource()
        securityScopedImportURL = nil
        pendingImportNavigator = nil
        pendingImportURL = nil
    }

    @MainActor public func routeToModuleWhenReady(
        _ module: NetworkModules,
        itemId: UUID? = nil,
        entryId: UUID? = nil
    ) {
        guard admitsExternalRoute(module, itemId: itemId, entryId: entryId) else { return }

        guard appNavigationModel.initialRouteType == .ready else {
            pendingExternalRoute = PendingExternalRoute(module: module, itemId: itemId, entryId: entryId)
            return
        }
        routeToModule(module, itemId: itemId, entryId: entryId)
    }

    /// Whether a route that came from outside the app (a link, a widget, a continued activity)
    /// should run: `false` for the same route within a second of the last one, which is one
    /// request delivered twice. Records the route. See CODE_AUDIT_21 §5.26.
    @MainActor public func admitsExternalRoute(
        _ module: NetworkModules,
        itemId: UUID? = nil,
        entryId: UUID? = nil
    ) -> Bool {
        let requestedRoute = PendingExternalRoute(module: module, itemId: itemId, entryId: entryId)
        let now = Date.now
        guard requestedRoute != lastExternalRoute
                || now.timeIntervalSince(lastExternalRouteDate) >= 1 else { return false }
        lastExternalRoute = requestedRoute
        lastExternalRouteDate = now
        return true
    }

    private func presentPendingExternalNavigationIfNeeded() {
        if let navigator = pendingImportNavigator, pendingImportURL != nil {
            pendingImportNavigator = nil
            navigator.navigate(to: SettingsRoute.importData, method: .managedCover)
        }
        if let navigator = pendingVTTImportNavigator, pendingVTTImportURL != nil {
            pendingVTTImportNavigator = nil
            presentVTTImport(with: navigator)
        }
        if let route = pendingExternalRoute {
            pendingExternalRoute = nil
            routeToModule(route.module, itemId: route.itemId, entryId: route.entryId)
        }
    }

    private func presentVTTImport(with navigator: Navigator) {
#if os(macOS)
        let target = settingsNavigator
        scenesManager.openSettingsWindow()
#else
        let target = gameNavigator
#endif

        Task { @MainActor in
            // A route sent before the target window's stack mounted is buffered and replayed
            // when it mounts (CODE_AUDIT_18 §3.17). The short delay is kept only so the
            // settings route has applied before the import cover is presented on top of it.
            // See CODE_AUDIT_20 §4.4.
            target.perform(route: KnownRoutes.settings)
            try? await Task.sleep(for: NavigationTiming.crossWindowRouteDelay)
            target.navigate(to: SettingsRoute.importData, method: .managedCover)
        }
    }

    @MainActor
    public func presentImportScreen() {
#if os(macOS)
        let target = settingsNavigator
        scenesManager.openSettingsWindow()
#else
        let target = gameNavigator
#endif

        Task { @MainActor in
            target.perform(route: KnownRoutes.settings)
            try? await Task.sleep(for: NavigationTiming.crossWindowRouteDelay)
            target.navigate(to: SettingsRoute.importData, method: .managedCover)
        }
    }

    @MainActor
    public func refreshTipEligibility() {
        MasterRPGTips.refreshEligibility(
            rootManager: root,
            databaseReady: appNavigationModel.initialRouteType == .ready
        )
    }

    func itemRootController(for module: NetworkModules) -> ItemRootController? {
        root.itemRootController(for: module)
    }

    /// Returns the Navigator that owns the window where the given module surfaces.
    /// - macOS: editor modules → `editorNavigator`, `.setting` → `settingsNavigator`, else `gameNavigator`.
    /// - visionOS: editor modules → `editorNavigator` (Settings stays in Game window), else `gameNavigator`.
    /// - iOS / iPadOS / tvOS: always `gameNavigator` (editor lives as tabs inside the Game window).
    @MainActor public func navigator(for module: NetworkModules) -> Navigator {
        navigator(forScene: module.sceneId)
    }

    /// Returns the root Navigator for the given window scene.
    ///
    /// Callers that have just opened a window for a module should resolve the
    /// navigator through this method so the navigator they get matches the window that's actually
    /// on screen — looking it up on the module before the window opens can yield the wrong one
    /// on platforms where module-to-window mapping is platform-conditional.
    ///
    /// Named `forScene:` rather than overloading `for:` so call sites passing leaf-static members
    /// (`.game`, `.search`, ...) don't become ambiguous between `NetworkModules` and `SceneId`.
    @MainActor public func navigator(forScene sceneId: SceneId) -> Navigator {
        switch sceneId {
        case .editor: return editorNavigator
        case .search: return searchNavigator
        case .settings: return settingsNavigator
        default: return gameNavigator
        }
    }

    public func resetNavigation() {
        guard let selectedTab: NetworkModules = selectedModule?.module else { return }
        let itemId: UUID? = root[selectedTab]?.currentSelectedItemId
        Task {
            try? await Task.sleep(for: NavigationTiming.crossWindowRouteDelay)
            navigator(for: selectedTab).perform(route: KnownRoutes.route(module: selectedTab, itemId: itemId, entryId: nil))
        }
    }


    @MainActor public var routeActions: RouteActions {
        RouteActions(id: .object(ObjectIdentifier(self))) { [weak self] module, itemId, entryId in
            guard let self, module != .none else { return }
            self.routeToModule(module, itemId: itemId, entryId: entryId)
        }
    }

    /// Opens the window that owns `module` (if needed) and performs the corresponding `KnownRoutes`
    /// route on that window's root navigator. A route sent before the new window's stack has
    /// subscribed is buffered by the navigator and replayed once it mounts (CODE_AUDIT_18 §3.17).
    ///
    /// Detail navigation rides through the route as a deep link: when `itemId` is non-nil the
    /// router emits `[.send(RootRoute.X), .reset, .send(ModuleRoute.detail(itemId))]`, and each
    /// module's root view has an `onNavigationReceive` for its own route type that writes the
    /// selection into `navigationModel.selectedItemId`. The 0.8s `assign` delay on the editor
    /// tab receiver gives the module body time to mount before the detail send fires.
    @MainActor public func routeToModule(_ module: NetworkModules, itemId: UUID? = nil, entryId: UUID? = nil) {
        guard module != .none else { return }
        let route = KnownRoutes.route(module: module, itemId: itemId, entryId: entryId)
        _ = scenesManager.openWindow(for: module)
        // When this opened a window, the route is buffered by the navigator until the new
        // window's stack has mounted, instead of a fixed delay that dropped it on slow
        // devices. See CODE_AUDIT_18 §3.17.
        navigator(for: module).perform(route: route)
    }
}

private struct PendingExternalRoute: Equatable {
    let module: NetworkModules
    let itemId: UUID?
    let entryId: UUID?
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
