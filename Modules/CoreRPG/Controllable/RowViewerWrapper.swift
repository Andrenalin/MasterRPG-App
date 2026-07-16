// @copyright André Trettin

import SwiftUI

/// Optimized wrapper for row viewer views - eliminates AnyView overhead.
public struct RowViewerWrapper<Controller: ViewControllable>: View, Equatable {
    let controller: Controller
    let source: ItemRowModel
    let destination: ItemRowModel

    public init(controller: Controller, source: ItemRowModel, destination: ItemRowModel) {
        self.controller = controller
        self.source = source
        self.destination = destination
    }

    public var body: some View {
        controller.rowViewer(source: source, destination: destination)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source && lhs.destination == rhs.destination
    }
}

#Preview("Row Viewer Wrapper") {
    RowViewerWrapper(
        controller: FakeViewController(),
        source: ItemRowModel(itemId: .fixture1, typeId: .none),
        destination: ItemRowModel(itemId: .fixture2, typeId: .none)
    )
}
