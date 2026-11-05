// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import Foundation
import Observation
import PhotoRPG

/// The weather the visionOS weather window shows: its photo in spatial 3D with the weather in
/// front of it.
@MainActor @Observable
public final class WeatherSpaceModel {
    /// The weather shown, `nil` before the first one.
    public internal(set) var selectedItemId: UUID?

    /// The weather's photo. The window's own model: the photo window keeps its own, since a
    /// spatial photo can be in only one window.
    @ObservationIgnored let imagePresentationModel = ImagePresentationModel()

    init() {}

    /// Shows a weather and starts loading and converting its photo.
    func show(itemId: UUID, photoId: UUID?) {
        selectedItemId = itemId
        imagePresentationModel.selectedItemId = photoId
    }
}

public extension WeatherRootModel {
    /// Shows a weather of the running game in the visionOS weather window. The caller opens
    /// the window.
    func showSpatialWeather(itemId: UUID) {
        weatherSpaceModel.show(itemId: itemId, photoId: gameController.gameItem(for: itemId).photoId)
    }
}
#endif
