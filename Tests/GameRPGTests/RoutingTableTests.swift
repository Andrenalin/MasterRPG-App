// @copyright André Trettin

#if canImport(Testing)
import AdventureRPG
import AudioRPG
import CharacterRPG
import CoreRPG
import DiceRPG
import Foundation
import MapRPG
import PdfRPG
import PhotoRPG
import RuleRPG
import SpaceRPG
import SwiftUI
import TableRPG
import Testing
import WeatherRPG

@testable import RolePlayGameKit

#if !os(tvOS)
import GeneratorRPG
#endif

/// CODE_AUDIT_TestGaps §5.6: which route every URL shape, window role and layout turns into. The
/// navigator is asked what each action would send, so the tables are checked without a window.
@MainActor
@Suite("Routing tables")
struct RoutingTableTests {
    // MARK: - Helpers

    private func described(_ value: any Hashable) -> String {
        "\(type(of: value)).\(value)"
    }

    /// What the actions send, in order: `RootRoute.audios`, `reset`, `AudioRoute.detail(…)`, `action`.
    private func describe(_ actions: [NavigationAction], on navigator: Navigator) -> [String] {
        actions.flatMap { action -> [String] in
            switch action(navigator) {
            case .inserting(let values):
                if !values.isEmpty, values.allSatisfy({ $0 is NavigationAction }) { return ["reset"] }
                return values.map(described)
            default:
                return ["action"]
            }
        }
    }

    private func actions(_ route: KnownRoutes, role: WindowRole, compact: Bool = false, appModel: AppModel) -> [String] {
        appModel.isCompactGameWindow = compact
        let router = WindowRouter(appModel: appModel, role: role)
        return describe(router.actions(for: route), on: appModel.gameNavigator)
    }

    /// The editor modules: the route, the module, the tab that shows it, and its detail route.
    private struct EditorModule {
        let name: String
        let module: NetworkModules
        let root: RootRoute
        let extended: ExtendedTabRoute
        let route: (UUID?) -> KnownRoutes
        let detail: (UUID) -> any Hashable
    }

    private var editorModules: [EditorModule] {
        var modules: [EditorModule] = [
            EditorModule(name: "audio", module: .audio, root: .audios, extended: .audios, route: { .audios($0, nil) }, detail: { AudioRoute.detail($0) }),
            EditorModule(name: "dice", module: .dice, root: .dice, extended: .dice, route: { .dice($0, nil) }, detail: { DiceRoute.detail($0) }),
            EditorModule(name: "map", module: .map, root: .maps, extended: .maps, route: { .maps($0, nil) }, detail: { MapRoute.detail($0) }),
            EditorModule(name: "pdf", module: .pdf, root: .pdfs, extended: .pdfs, route: { .pdfs($0, nil) }, detail: { PdfRoute.detail($0) }),
            EditorModule(name: "photo", module: .photo, root: .photos, extended: .photos, route: { .photos($0, nil) }, detail: { PhotoRoute.detail($0) }),
            EditorModule(name: "rule", module: .rule, root: .rules, extended: .rules, route: { .rules($0, nil) }, detail: { RuleRoute.detail($0) }),
            EditorModule(name: "space", module: .space, root: .space, extended: .space, route: { .spaces($0, nil) }, detail: { SpaceRoute.detail($0) }),
            EditorModule(name: "table", module: .table, root: .tables, extended: .tables, route: { .tables($0, nil) }, detail: { TableRoute.detail($0) }),
            EditorModule(name: "weather", module: .weather, root: .weathers, extended: .weathers, route: { .weathers($0, nil) }, detail: { WeatherRoute.detail($0) })
        ]
#if !os(tvOS)
        modules.append(EditorModule(name: "generator", module: .generator, root: .generator, extended: .generator, route: { .generators($0, nil) }, detail: { GeneratorRoute.detail($0) }))
#endif
        return modules
    }

    // MARK: - KnownRoutes

    @Test("Every module maps to its own route, with the item and the entry")
    func knownRouteForEveryModule() {
        let item = UUID()
        let entry = UUID()

        #expect(KnownRoutes.route(module: .adventure, itemId: item, entryId: entry) == .adventures(item, entry))
        #expect(KnownRoutes.route(module: .audio, itemId: item, entryId: entry) == .audios(item, entry))
        #expect(KnownRoutes.route(module: .dice, itemId: item, entryId: entry) == .dice(item, entry))
        #expect(KnownRoutes.route(module: .generator, itemId: item, entryId: entry) == .generators(item, entry))
        #expect(KnownRoutes.route(module: .map, itemId: item, entryId: entry) == .maps(item, entry))
        #expect(KnownRoutes.route(module: .pdf, itemId: item, entryId: entry) == .pdfs(item, entry))
        #expect(KnownRoutes.route(module: .photo, itemId: item, entryId: entry) == .photos(item, entry))
        #expect(KnownRoutes.route(module: .rule, itemId: item, entryId: entry) == .rules(item, entry))
        #expect(KnownRoutes.route(module: .space, itemId: item, entryId: entry) == .spaces(item, entry))
        #expect(KnownRoutes.route(module: .table, itemId: item, entryId: entry) == .tables(item, entry))
        #expect(KnownRoutes.route(module: .value, itemId: item, entryId: entry) == .values(item, entry))
        #expect(KnownRoutes.route(module: .weather, itemId: item, entryId: entry) == .weathers(item, entry))
        // The modules without an item ignore it, and an unknown module shows the game.
        #expect(KnownRoutes.route(module: .game, itemId: item, entryId: entry) == .game)
        #expect(KnownRoutes.route(module: .search, itemId: item, entryId: entry) == .search)
        #expect(KnownRoutes.route(module: .setting, itemId: item, entryId: entry) == .settings)
        #expect(KnownRoutes.route(module: .none, itemId: item, entryId: entry) == .game)
    }

    @Test("A module and its tab or root route name each other")
    func routeEnumsRoundTrip() {
        for module in editorModules {
            #expect(RootRoute(networkModule: module.module) == module.root, "\(module.name)")
            #expect(module.root.module == module.module, "\(module.name)")
            #expect(ExtendedTabRoute(networkModule: module.module) == module.extended, "\(module.name)")
        }
        #expect(RootRoute(networkModule: .none) == .game)
        #expect(ExtendedTabRoute(networkModule: .game) == .settings)
        #expect(RootRoute(rawValue: NetworkModules.map.token) == .maps)
        #expect(RootRoute(rawValue: "nonsense") == nil)
    }

#if os(iOS)
    // MARK: - Game window on iOS / iPadOS

    @Test("On a regular layout a module surfaces as a root route, with the item pushed after a reset")
    func regularLayoutRoutes() {
        let appModel = AppModel.preview
        let item = UUID()

        for module in editorModules {
            let withItem = actions(module.route(item), role: .game, compact: false, appModel: appModel)
            let without = actions(module.route(nil), role: .game, compact: false, appModel: appModel)

            #expect(withItem == [described(module.root), "reset", described(module.detail(item))], "\(module.name) with an item")
            #expect(without == [described(module.root)], "\(module.name) without an item keeps the selection")
        }
    }

    @Test("On a compact layout a module surfaces through the editors tab")
    func compactLayoutRoutes() {
        let appModel = AppModel.preview
        let item = UUID()

        for module in editorModules {
            let withItem = actions(module.route(item), role: .game, compact: true, appModel: appModel)
            let without = actions(module.route(nil), role: .game, compact: true, appModel: appModel)

            #expect(withItem == [described(RootRoute.editors), "reset", described(module.extended), described(module.detail(item))], "\(module.name) with an item")
            #expect(without == [described(RootRoute.editors), described(module.extended)], "\(module.name) without an item")
        }
    }

    @Test("Adventures, Characters, the game and search are top-level in both layouts")
    func topLevelRoutesIgnoreTheLayout() {
        let appModel = AppModel.preview
        let item = UUID()

        for compact in [false, true] {
            #expect(actions(.adventures(item, nil), role: .game, compact: compact, appModel: appModel)
                == [described(RootRoute.adventures), "reset", described(AdventureRoute.detail(item))])
            #expect(actions(.adventures(nil, nil), role: .game, compact: compact, appModel: appModel) == [described(RootRoute.adventures)])
            #expect(actions(.values(item, nil), role: .game, compact: compact, appModel: appModel)
                == [described(RootRoute.values), "reset", described(CharacterRoute.detail(item))])
            #expect(actions(.values(nil, nil), role: .game, compact: compact, appModel: appModel) == [described(RootRoute.values)])
            #expect(actions(.game, role: .game, compact: compact, appModel: appModel) == [described(RootRoute.game)])
            #expect(actions(.search, role: .game, compact: compact, appModel: appModel) == [described(RootRoute.search)])
            #expect(actions(.settings, role: .game, compact: compact, appModel: appModel)
                == [described(RootRoute.editors), "reset", described(ExtendedTabRoute.settings)])
        }
    }

    @Test("A route sent to the game window of this platform reaches every module's navigator")
    func everyModuleLivesInTheGameWindow() {
        let appModel = AppModel.preview

        for module in NetworkModules.allCases where module != .none {
            #expect(appModel.navigator(for: module) === appModel.gameNavigator, "\(module)")
        }
        #expect(appModel.navigator(forScene: .editor) === appModel.editorNavigator)
        #expect(appModel.navigator(forScene: .search) === appModel.searchNavigator)
        #expect(appModel.navigator(forScene: .settings) === appModel.settingsNavigator)
        #expect(appModel.navigator(forScene: .game) === appModel.gameNavigator)
    }
#endif

    // MARK: - Editor, search and settings windows

    @Test("The editor window switches the tab and writes the selection after it")
    func editorWindowSelectsTheItem() {
        let appModel = AppModel.preview
        let item = UUID()

        for module in editorModules {
            let withItem = actions(module.route(item), role: .editor, appModel: appModel)
            let without = actions(module.route(nil), role: .editor, appModel: appModel)

            #expect(withItem == [described(module.root), "action"], "\(module.name) with an item")
            #expect(without == [described(module.root)], "\(module.name) without an item")
            // The action is what writes the selection onto the module.
            #expect(appModel.itemRootController(for: module.module)?.navigationModel.selectedItemId == item, "\(module.name) selection")
            appModel.itemRootController(for: module.module)?.navigationModel.selectedItemId = nil
        }
    }

    @Test("The editor window routes Adventures and Characters through their own root route too")
    func editorWindowHandlesAdventuresAndValues() {
        let appModel = AppModel.preview
        let item = UUID()

        #expect(actions(.adventures(item, nil), role: .editor, appModel: appModel) == [described(RootRoute.adventures), "action"])
        #expect(actions(.values(nil, nil), role: .editor, appModel: appModel) == [described(RootRoute.values)])
        #expect(appModel.itemRootController(for: .adventure)?.navigationModel.selectedItemId == item)
    }

    @Test("The search and settings windows handle their own route and hand the rest on")
    func searchAndSettingsWindows() {
        let appModel = AppModel.preview

        #expect(actions(.search, role: .search, appModel: appModel) == [described(RootRoute.search)])
        #expect(actions(.settings, role: .settings, appModel: appModel) == [described(RootRoute.settings)])
        // Anything else is forwarded to the window that owns it: nothing is sent here.
        #expect(actions(.maps(UUID(), nil), role: .search, appModel: appModel).isEmpty)
        #expect(actions(.search, role: .settings, appModel: appModel).isEmpty)
    }

    // MARK: - RootURLHandler

    private func handler(_ appModel: AppModel) -> RootURLHandler {
        RootURLHandler(appModel: appModel, role: .game)
    }

    private func deeplink(_ module: NetworkModules, item: UUID? = nil, entry: UUID? = nil) -> URL {
        var text = "RPG://\(module.token)/0"
        if let item { text += "/\(item.uuidString)" }
        if item != nil, let entry { text += "/\(entry.uuidString)" }
        return URL(string: text).unsafelyUnwrapped
    }

    @Test("Every module's deep link before the database is ready waits as the pending route")
    func deepLinkWaitsForTheDatabase() throws {
        for module in [NetworkModules.map, .audio, .adventure, .value, .weather] {
            let appModel = AppModel.previewWithoutDatabase
            try #require(appModel.appNavigationModel.initialRouteType != .ready)
            let item = UUID()
            let entry = UUID()

            let handled = handler(appModel).handles(deeplink(module, item: item, entry: entry), with: appModel.gameNavigator)

            #expect(handled, "\(module)")
            #expect(appModel.pendingExternalRoute == PendingExternalRoute(module: module, itemId: item, entryId: entry), "\(module)")
        }
    }

    @Test("A deep link without an item or with a malformed one still routes to the module")
    func deepLinkShapes() throws {
        let appModel = AppModel.previewWithoutDatabase
        let url = handler(appModel)

        #expect(url.handles(deeplink(.map), with: appModel.gameNavigator))
        #expect(appModel.pendingExternalRoute == PendingExternalRoute(module: .map, itemId: nil, entryId: nil))

        let malformed = try #require(URL(string: "RPG://\(NetworkModules.dice.token)/0/not-a-uuid/also-not"))
        #expect(url.handles(malformed, with: appModel.gameNavigator))
        #expect(appModel.pendingExternalRoute == PendingExternalRoute(module: .dice, itemId: nil, entryId: nil))

        // The scheme and the module are case-insensitive.
        let lowercase = try #require(URL(string: "rpg://\(NetworkModules.table.token.lowercased())/0"))
        #expect(url.handles(lowercase, with: appModel.gameNavigator))
        #expect(appModel.pendingExternalRoute?.module == .table)
    }

    @Test("A link the app does not own is not handled")
    func foreignLinksAreNotHandled() throws {
        let appModel = AppModel.previewWithoutDatabase
        let url = handler(appModel)
        let item = UUID()

        let notHandled: [String] = [
            "https://example.com/\(NetworkModules.map.token)/0/\(item.uuidString)",
            "RPG://nonsense/0/\(item.uuidString)",
            "mailto:someone@example.com",
            // A web address that merely ends in a document extension is no document.
            "https://example.com/adventure.gmz",
            "https://example.com/dungeon.uvtt"
        ]
        for text in notHandled {
            let link = try #require(URL(string: text))
            #expect(!url.handles(link, with: appModel.gameNavigator), "\(text)")
        }
        #expect(appModel.pendingExternalRoute == nil)
        #expect(appModel.pendingImportUrl == nil)
        #expect(appModel.pendingVTTImportUrl == nil)
    }

    @Test("A document file opens the import, case-insensitively, and waits for the database")
    func documentFilesOpenTheImport() throws {
        let appModel = AppModel.previewWithoutDatabase
        let url = handler(appModel)
        let gmz = URL.temporaryDirectory.appending(path: "Adventure.GMZ")

        #expect(url.handles(gmz, with: appModel.gameNavigator))

        #expect(appModel.pendingImportUrl == gmz)
        #expect(appModel.pendingImportNavigator === appModel.gameNavigator)
        #expect(appModel.pendingVTTImportUrl == nil)
        #expect(appModel.pendingExternalRoute == nil)
        appModel.finishImportPresentation()
        #expect(appModel.pendingImportUrl == nil)
        #expect(appModel.pendingImportNavigator == nil)
    }

    @Test("A VTT file opens the VTT import, whatever its extension's case", arguments: ["map.uvtt", "map.DD2VTT", "world.mrpgfoundry"])
    func vttFilesOpenTheVTTImport(name: String) {
        let appModel = AppModel.previewWithoutDatabase
        let file = URL.temporaryDirectory.appending(path: name)

        #expect(handler(appModel).handles(file, with: appModel.gameNavigator))

        #expect(appModel.pendingVTTImportUrl == file)
        #expect(appModel.pendingVTTImportNavigator === appModel.gameNavigator)
        #expect(appModel.pendingImportUrl == nil)
    }

    @Test("A file of another kind is no import")
    func otherFilesAreNotHandled() {
        let appModel = AppModel.previewWithoutDatabase

        #expect(!handler(appModel).handles(URL.temporaryDirectory.appending(path: "notes.txt"), with: appModel.gameNavigator))
        #expect(appModel.pendingImportUrl == nil)
        #expect(appModel.pendingVTTImportUrl == nil)
    }

    @Test("The same document delivered twice keeps the first import request")
    func sameDocumentTwiceIsOneRequest() {
        let appModel = AppModel.previewWithoutDatabase
        let gmz = URL.temporaryDirectory.appending(path: "Adventure.gmz")
        appModel.presentImport(gmz, with: appModel.gameNavigator)

        appModel.presentImport(gmz, with: appModel.editorNavigator)

        #expect(appModel.pendingImportNavigator === appModel.gameNavigator)
    }

    @Test("Once the database is ready a deep link is admitted once within a second")
    func readyDeepLinkIsDeduplicated() throws {
        let appModel = AppModel.preview
        try #require(appModel.appNavigationModel.initialRouteType == .ready)
        let item = UUID()
        let link = deeplink(.map, item: item)

        #expect(handler(appModel).handles(link, with: appModel.gameNavigator))
        let firstDate = appModel.lastExternalRouteDate
        #expect(appModel.lastExternalRoute == PendingExternalRoute(module: .map, itemId: item, entryId: nil))
        #expect(appModel.pendingExternalRoute == nil, "nothing waits when the app is ready")

        // Delivered a second time (scene delegate and SwiftUI): handled, but not routed again.
        #expect(handler(appModel).handles(link, with: appModel.gameNavigator))
        #expect(appModel.lastExternalRouteDate == firstDate)
    }

    // MARK: - AppModel routing

    @Test("A route that comes in before the database is ready is replayed once it is")
    func pendingRouteIsReplayedWhenReady() {
        let appModel = AppModel.previewWithoutDatabase
        let item = UUID()

        appModel.routeToModuleWhenReady(.pdf, itemId: item)

        #expect(appModel.pendingExternalRoute == PendingExternalRoute(module: .pdf, itemId: item, entryId: nil))
        appModel.appNavigationModel.initialRouteType = .ready
        appModel.presentPendingExternalNavigationIfNeeded()
        #expect(appModel.pendingExternalRoute == nil)
    }

    @Test("A pending import is presented through its navigator and cleared once")
    func pendingImportIsPresentedOnce() {
        let appModel = AppModel.previewWithoutDatabase
        let gmz = URL.temporaryDirectory.appending(path: "Adventure.gmz")
        appModel.presentImport(gmz, with: appModel.gameNavigator)
        #expect(appModel.pendingImportNavigator != nil)

        appModel.appNavigationModel.initialRouteType = .ready
        appModel.presentPendingExternalNavigationIfNeeded()

        #expect(appModel.pendingImportNavigator == nil)
        #expect(appModel.pendingImportUrl == gmz, "the URL stays until the import screen is finished")
    }

    @Test("The same pending route replaced by a newer one keeps only the newer")
    func newerPendingRouteWins() {
        let appModel = AppModel.previewWithoutDatabase
        let first = UUID()
        let second = UUID()

        appModel.routeToModuleWhenReady(.map, itemId: first)
        appModel.lastExternalRouteDate = .distantPast
        appModel.routeToModuleWhenReady(.photo, itemId: second)

        #expect(appModel.pendingExternalRoute == PendingExternalRoute(module: .photo, itemId: second, entryId: nil))
    }

    @Test("A continued Handoff activity routes to the module it names")
    func continueHandoffActivity() {
        let appModel = AppModel.previewWithoutDatabase
        let item = UUID()
        let child = UUID()
        let activity = NSUserActivity(activityType: UserActivity.bundleIdentifierType)
        UserActivity.addPayLoad(for: activity, title: "Goblin", module: .value, itemId: item, childId: child)

        let handled = appModel.continueActivity(activity)

        #expect(handled)
        #expect(appModel.pendingExternalRoute == PendingExternalRoute(module: .value, itemId: item, entryId: child))
    }

    @Test("An activity of the app without a module or an item is not handled")
    func incompleteActivityIsNotHandled() {
        let appModel = AppModel.previewWithoutDatabase
        let noItem = NSUserActivity(activityType: UserActivity.bundleIdentifierType)
        noItem.userInfo = [UserActivity.moduleKey: NetworkModules.map.token]
        let noModule = NSUserActivity(activityType: UserActivity.bundleIdentifierType)
        noModule.userInfo = [UserActivity.itemKey: UUID().uuidString]

        #expect(!appModel.continueActivity(noItem))
        #expect(!appModel.continueActivity(noModule))
        #expect(appModel.pendingExternalRoute == nil)
    }

    @Test("An activity of another app is not handled")
    func foreignActivityIsNotHandled() {
        let appModel = AppModel.previewWithoutDatabase
        let activity = NSUserActivity(activityType: "com.example.browsing")
        activity.userInfo = [UserActivity.moduleKey: NetworkModules.map.token, UserActivity.itemKey: UUID().uuidString]

        #expect(!appModel.continueActivity(activity))
        #expect(appModel.pendingExternalRoute == nil)
    }

    // MARK: - Layout change

    @Test("A layout change remembers the module on screen, and the editors tab remembers the module it hosts")
    func layoutChangeRemembersTheModule() {
        let appModel = AppModel.preview

        appModel.selectedModule = .maps
        appModel.rememberRouteForLayoutChange()
        #expect(appModel.layoutRestoreTarget?.module == .map)

        appModel.selectedModule = .editors
        appModel.selectedExtendedModule = .photos
        appModel.rememberRouteForLayoutChange()
        #expect(appModel.layoutRestoreTarget?.module == .photo)

        appModel.layoutRestoreTarget = nil
        appModel.selectedModule = nil
        appModel.rememberRouteForLayoutChange()
        #expect(appModel.layoutRestoreTarget == nil, "nothing on screen: nothing to restore")
    }

    @Test("A regular layout selects the remembered module and clears the target")
    func regularLayoutRestoresTheTab() {
        let appModel = AppModel.preview
        appModel.selectedModule = .game
        appModel.layoutRestoreTarget = LayoutRestoreTarget(module: .table, itemId: UUID())

        appModel.restoreRouteAfterLayoutChange(isCompact: false)

        #expect(appModel.selectedModule == .tables)
        #expect(appModel.layoutRestoreTarget == nil)
    }

    @Test("A compact layout leaves the tab to the editors route and clears the target")
    func compactLayoutRestoresThroughTheEditorsTab() {
        let appModel = AppModel.preview
        appModel.selectedModule = .game
        appModel.layoutRestoreTarget = LayoutRestoreTarget(module: .table, itemId: nil)

        appModel.restoreRouteAfterLayoutChange(isCompact: true)

        #expect(appModel.selectedModule == .game)
        #expect(appModel.layoutRestoreTarget == nil)
    }

    @Test("Restoring without a remembered target does nothing")
    func restoreWithoutTarget() {
        let appModel = AppModel.preview
        appModel.selectedModule = .dice

        appModel.restoreRouteAfterLayoutChange(isCompact: false)

        #expect(appModel.selectedModule == .dice)
    }
}
#endif
