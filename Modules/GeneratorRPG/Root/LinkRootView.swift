// @copyright André Trettin

import CoreRPG
import SwiftUI

typealias LinkRootView = ModuleLinkRootView<GeneratorRootModel>

#Preview(traits: .mockData) {
    LinkRootView(type: .window, itemSelectionModel: ItemSelectionModel())
}
