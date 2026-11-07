// @copyright André Trettin

import CoreRPG
import SwiftUI

typealias LinkRootView = ModuleLinkRootView<WeatherRootModel>

#Preview(traits: .mockData) {
    LinkRootView(type: .window, itemSelectionModel: ItemSelectionModel())
}
