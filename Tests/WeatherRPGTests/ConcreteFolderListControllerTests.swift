// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import PhotoRPG
@testable import WeatherRPG

@MainActor
struct ConcreteFolderListControllerTests {
    @Test func routesAndCopy() async throws {
        let root = WeatherRootModel.testRoot(photoRoot: PhotoRootModel.testRoot())
        let sut = try #require(root.folderListController as? WeatherRPG.FolderListController)
        let itemId = UUID()

        #expect((sut.detailDestination(for: itemId) as? WeatherRoute) == .detail(itemId))
        #expect((sut.folderDestination(for: itemId) as? WeatherDetailRoute) == .folder(itemId))
        #expect((sut.folderInlineDestination(for: itemId) as? WeatherDetailRoute) == .folderInline(itemId))
        #expect((sut.viewerDestination(for: itemId) as? WeatherRPG.DetailRoute) == .viewer(itemId))

        let replacement = FolderListModel(navigationModel: ModuleNavigationModel())
        let copied = sut.copy(listModel: replacement)
        #expect(copied.listModel === replacement)
        #expect(copied.listDisplayModel !== sut.listDisplayModel)
    }
}
#endif
