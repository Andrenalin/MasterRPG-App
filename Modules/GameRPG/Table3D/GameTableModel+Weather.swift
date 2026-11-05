// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import Foundation
import RealityKit
import SwiftUI
import WeatherRPG

// The weather the game master shows, in 3D over the map: rain or snow, clouds, stars and
// lightning, without the weather's photo. See `TableWeatherState` for when it shows.

extension GameTableModel {
    /// Shows `weather` over the map, or removes it for `nil`. Idempotent: it runs again after
    /// each map change, since the weather covers the map's footprint.
    func updateWeather(_ weather: WeatherModel?, reduceMotion: Bool, dimFlashingLights: Bool) {
        weatherEffect.show(
            weather,
            in: weatherVolume,
            reduceMotion: reduceMotion,
            dimFlashingLights: dimFlashingLights
        )
    }

    /// The box over the map the weather fills, in the weather entity's parent space.
    var weatherVolume: WeatherVolume {
        let footprint = weatherFootprint
#if os(visionOS)
        // On the table top, under the 1.5 m tall volume's ceiling.
        return WeatherVolume(
            width: footprint.width,
            depth: footprint.depth,
            floorY: 0,
            height: Self.volumeWeatherHeight,
            cloudOpacityLimit: Self.volumeCloudOpacityLimit
        )
#else
        // The camera looks down through the clouds: fainter clouds keep the map readable.
        return WeatherVolume(
            width: footprint.width,
            depth: footprint.depth,
            floorY: GameMetrics.tableThickness,
            height: Self.flatWeatherHeight,
            cloudOpacityLimit: Self.flatCloudOpacityLimit
        )
#endif
    }

    /// The map's plane on the table, or the largest map's before one is loaded.
    private var weatherFootprint: (width: Float, depth: Float) {
        guard let mapImage = currentMapImage,
              let canvasSize = MapTableProjection.canvasSize(
                  map: currentMapModel(),
                  image: mapImage,
                  degrees: currentMapDegrees
              )
        else { return (MapTableProjection.maxPlaneWidth, MapTableProjection.maxPlaneDepth) }
        let projection = MapTableProjection(
            imageSize: canvasSize,
            planeAspectRatio: MapTableProjection.planeAspectRatio(
                photoSize: mapImage.size,
                degrees: currentMapDegrees,
                canvasSize: canvasSize
            )
        )
        return (projection.planeWidth, projection.planeDepth)
    }

    /// Adds the weather to the table: on the table top on visionOS, on the table's root on the
    /// camera-based table.
    func attachWeather() {
#if os(visionOS)
        renderer.tableTopEntity.addChild(weatherEffect.entity)
#else
        renderer.root.addChild(weatherEffect.entity)
#endif
    }

    private static let volumeWeatherHeight: Float = 0.5
    private static let volumeCloudOpacityLimit: Float = 0.9
    private static let flatWeatherHeight: Float = 0.35
    private static let flatCloudOpacityLimit: Float = 0.45
}

/// Keeps a table's 3D weather in step with the game master's table weather, the map under it
/// and the viewer's motion and flashing-light settings. Shared by the visionOS volume and the
/// camera-based table.
@MainActor
struct GameTableWeatherSync: ViewModifier {
    let root: GameRoot
    let game: GameTableModel?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDimFlashingLights) private var dimFlashingLights

    private struct Key: Equatable {
        let hasGame: Bool
        let weatherId: UUID?
        let mapId: UUID?
        let mapSize: CGSize?
        let mapDegrees: Double?
        let reduceMotion: Bool
        let dimFlashingLights: Bool
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: key, initial: true) { _, key in
                guard let game else { return }
                game.updateWeather(
                    key.weatherId.map { root.weatherRoot.gameWeather(itemId: $0) },
                    reduceMotion: key.reduceMotion,
                    dimFlashingLights: key.dimFlashingLights
                )
            }
    }

    private var key: Key {
        Key(
            hasGame: game != nil,
            weatherId: root.gameModel.playerController?.gameModel.tableWeather.visibleWeatherId,
            mapId: game?.currentMapId,
            mapSize: game?.currentMapImage?.size,
            mapDegrees: game?.currentMapDegrees,
            reduceMotion: reduceMotion,
            dimFlashingLights: dimFlashingLights
        )
    }
}
#endif
