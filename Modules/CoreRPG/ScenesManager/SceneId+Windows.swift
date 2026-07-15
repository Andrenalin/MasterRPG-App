// @copyright André Trettin

import Foundation

extension SceneId {
    public static var additionalEditor: Self { .init(rawValue: "additionalEditor") }
    public static var adventureViewer: Self { .init(rawValue: "adventureViewer") }
    public static var editor: Self { .init(rawValue: "editor") }
    public static var game: Self { .init(rawValue: "game") }
    public static var gameStatistics: Self { .init(rawValue: "gameStatistics") }
    public static var gameTable: Self { .init(rawValue: "gameTable") }
    public static var generateAdventure: Self { .init(rawValue: "generateAdventure") }
    public static var imageSpaceViewer: Self { .init(rawValue: "imageSpaceViewer") }
    public static var logs: Self { .init(rawValue: "logs") }
    public static var mapEditor: Self { .init(rawValue: "mapEditor") }
    public static var mapTileEditor: Self { .init(rawValue: "mapTileEditor") }
    public static var pdfViewer: Self { .init(rawValue: "pdfViewer") }
    public static var photoViewer: Self { .init(rawValue: "photoViewer") }
    public static var search: Self { .init(rawValue: "search") }
    public static var settings: Self { .init(rawValue: "settings") }
    public static var spaceViewer: Self { .init(rawValue: "spaceViewer") }
    public static var tableViewer: Self { .init(rawValue: "tableViewer") }
    public static var valueViewer: Self { .init(rawValue: "valueViewer") }
    public static var weatherViewer: Self { .init(rawValue: "weatherViewer") }
    
    
    public static func sceneId(for networkModule: NetworkModules) -> SceneId {
        SceneId(rawValue: networkModule.linkWindowId)
    }
    
    public static func viewerId(for networkModule: NetworkModules) -> SceneId {
        SceneId(rawValue: networkModule.viewerWindowId)
    }
}
