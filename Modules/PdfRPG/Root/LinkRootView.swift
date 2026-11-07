// @copyright André Trettin

import CoreRPG
import SwiftUI

typealias LinkRootView = ModuleLinkRootView<PdfRootModel>

#Preview(traits: .mockData) {
    LinkRootView(type: .window, itemSelectionModel: ItemSelectionModel())
}
