// @copyright André Trettin

import Foundation
import SwiftUI

/// Optimized wrapper for sharing views - eliminates AnyView overhead.
public struct SharingViewWrapper<Controller: ViewControllable>: View {
    let controller: Controller
    let itemId: UUID

    public init(controller: Controller, itemId: UUID) {
        self.controller = controller
        self.itemId = itemId
    }

    public var body: some View {
        controller.sharingView(for: itemId)
    }
}

#Preview("Sharing Wrapper") {
    SharingViewWrapper(controller: FakeViewController(), itemId: .fixture1)
}
