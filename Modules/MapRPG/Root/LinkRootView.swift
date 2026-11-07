// @copyright André Trettin

import CoreRPG
import SwiftUI

typealias LinkRootView = ModuleLinkRootView<MapRootModel>

#Preview(traits: .mockData) {
    LinkRootView(type: .window, itemSelectionModel: ItemSelectionModel())
}
