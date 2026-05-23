// @copyright André Trettin

import CoreRPG
import SwiftUI

struct WeatherEditor: View {
    let model: WeatherModel

    var body: some View {
        WeatherPhotoEditor(model: model)
        WeatherConditionEditor(model: model)
        WeatherStormEditor(model: model)
        WeatherThunderEditor(model: model)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(WeatherRootModel.self) var root

    WeatherEditor(model: root.itemController.itemOrEmpty(for: MockData.previewId))
}
