// @copyright André Trettin


import CoreRPG
import CoreData
import Observation
import SwiftData
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
    @ObservationIgnored public let scenesManager: ScenesManager

    @ObservationIgnored public let optionKeyDownModel: OptionKeyDownModel
    @ObservationIgnored public var rpgSpotlightIndexer: RpgSpotlightIndexerDelegate?
    @ObservationIgnored public let settingsModel: AppSettingsModel
    
    // Database
    public var coreDataInitModel: CoreDataInitModel?
    /// File handed to the app through Open In; consumed by the Foundry import screen.
    public var pendingVTTImportURL: URL?
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
        self.scenesManager = ScenesManager()
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
        
        let tableRoot = TableFactory.root(tagController: tagController, diceRoot: diceRoot, pdfRoot: pdfRoot)
        let weatherRoot = WeatherRootFactory.root(tagController: tagController, photoRoot: photoRoot)
        
        let characterRoot = CharacterRootFactory.root(tagController: tagController, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        
        let mapRoot = MapRootFactory.root(tagController: tagController, audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, characterRoot: characterRoot)

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
 
// MARK: - Maintanence

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
        try? await adventureRoot.itemDataCleanup()
        try? await audioRoot.itemDataCleanup()
        try? await characterRoot.itemDataCleanup()
        try? await diceRoot.itemDataCleanup()
        try? await mapRoot.itemDataCleanup()
        try? await pdfRoot.itemDataCleanup()
        try? await photoRoot.itemDataCleanup()
        try? await ruleRoot.itemDataCleanup()
        try? await tableRoot.itemDataCleanup()
        try? await spaceRoot.itemDataCleanup()
        try? await weatherRoot.itemDataCleanup()
    }

    public func installExampleData(isGerman: Bool = false) {
        let importController = adventureRoot.importControllable
        let bundle = RPGResources.Resources.bundle
        let name = isGerman ? RPGResources.Resources.exampleFirstGermanData : RPGResources.Resources.exampleFirstData
        guard let url = bundle.url(forResource: name, withExtension: "gmz") else { return }
        let task = importController.importUrl(from: url)
        Task {
            let _ = await task.result
        }
    }

    func loadFreePackages(tag: String) {
        let importController = adventureRoot.importControllable
        let bundle = RPGResources.Resources.bundle
        guard let url = bundle.url(forResource: tag, withExtension: "gmz") else { return }
        let task = importController.importUrl(from: url)
        Task {
            let _ = await task.result
        }
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
            fatalError()
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
    @MainActor public func setupRootModels(context: NSManagedObjectContext, batchContext: NSManagedObjectContext?, spotlightIndexer: RpgSpotlightIndexerDelegate?, coreDataInitModel: CoreDataInitModel?) {
        tagController.setup(context: context)
        adventureRoot.setUp(root: root, context: context, batchContext: batchContext)
        gameRoot.setUpStatistics(context: context)

        self.rpgSpotlightIndexer = spotlightIndexer
        spotlightIndexer?.observeIndexing()
        
        self.coreDataInitModel = coreDataInitModel

        self.appNavigationModel.initialRouteType = .ready
        presentPendingExternalNavigationIfNeeded()
    }
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
        let requestedRoute = PendingExternalRoute(
            module: module,
            itemId: itemId,
            entryId: entryId
        )
        let now = Date.now
        guard requestedRoute != lastExternalRoute
                || now.timeIntervalSince(lastExternalRouteDate) >= 1 else { return }
        lastExternalRoute = requestedRoute
        lastExternalRouteDate = now

        guard appNavigationModel.initialRouteType == .ready else {
            pendingExternalRoute = requestedRoute
            return
        }
        routeToModule(module, itemId: itemId, entryId: entryId)
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
            if target !== navigator {
                try? await Task.sleep(for: NavigationTiming.crossWindowRouteDelay)
            }
            target.perform(route: KnownRoutes.settings)
            try? await Task.sleep(for: NavigationTiming.crossWindowRouteDelay)
            target.navigate(to: SettingsRoute.importData, method: .managedCover)
        }
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
    /// Callers that have just opened a window via `openWindowForModule(...)` should resolve the
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


    @MainActor var externalRouter: any NavigationRouting<KnownRoutes> {
        NavigationRouter(gameNavigator) { route in
            switch route {
            case .adventures:
                self.navigator(for: .adventure).perform(route: KnownRoutes.adventures(nil, nil))
            case .audios:
                self.navigator(for: .audio).perform(route: KnownRoutes.audios(nil, nil))
            default:
                break
            }
        }
    }

    @MainActor public var routeActions: RouteActions {
        RouteActions { [weak self] module, itemId, entryId in
            guard let self, module != .none else { return }
            self.routeToModule(module, itemId: itemId, entryId: entryId)
        }
    }

    /// Opens the window that owns `module` (if needed) and performs the corresponding `KnownRoutes`
    /// route on that window's root navigator. On multi-window platforms, waits 150ms after opening
    /// so the navigation stack has time to mount before the route is sent — performing the route
    /// before the stack subscribes drops it on the floor.
    ///
    /// Detail navigation rides through the route as a deep link: when `itemId` is non-nil the
    /// router emits `[.send(RootRoute.X), .reset, .send(ModuleRoute.detail(itemId))]`, and each
    /// module's root view has an `onNavigationReceive` for its own route type that writes the
    /// selection into `navigationModel.selectedItemId`. The 0.8s `assign` delay on the editor
    /// tab receiver gives the module body time to mount before the detail send fires.
    @MainActor public func routeToModule(_ module: NetworkModules, itemId: UUID? = nil, entryId: UUID? = nil) {
        guard module != .none else { return }
        let route = KnownRoutes.route(module: module, itemId: itemId, entryId: entryId)
        let opening = scenesManager.openWindow(for: module)
        let rootNavigator = navigator(for: module)
        if opening {
            Task { @MainActor in
                try? await Task.sleep(for: NavigationTiming.crossWindowRouteDelay)
                rootNavigator.perform(route: route)
            }
        } else {
            rootNavigator.perform(route: route)
        }
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
        model.setupRootModels(context: dbModel.context.unsafelyUnwrapped, batchContext: dbModel.batchContext, spotlightIndexer: nil, coreDataInitModel: nil)
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
