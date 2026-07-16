// @copyright André Trettin

import Foundation
import SwiftUI

/// Optimized wrapper for thumbnail row views - eliminates AnyView overhead.
public struct ThumbnailRowViewWrapper<Controller: ViewControllable>: View, Equatable {
    let controller: Controller
    let itemId: UUID

    public init(controller: Controller, itemId: UUID) {
        self.controller = controller
        self.itemId = itemId
    }

    public var body: some View {
        controller.thumbnailRowView(for: itemId)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemId == rhs.itemId
    }
}

#Preview("Thumbnail Wrapper") {
    ThumbnailRowViewWrapper(controller: FakeViewController(), itemId: .fixture1)
}
