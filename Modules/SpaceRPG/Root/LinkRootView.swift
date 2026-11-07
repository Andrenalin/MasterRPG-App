// @copyright André Trettin

import CoreRPG
import SwiftUI

typealias LinkRootView = ModuleLinkRootView<SpaceRootModel>

#Preview(traits: .mockData) {
    LinkRootView(type: .window, itemSelectionModel: ItemSelectionModel())
}
