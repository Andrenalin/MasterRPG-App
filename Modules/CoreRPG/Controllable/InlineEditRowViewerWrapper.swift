// @copyright André Trettin

import SwiftUI

/// Optimized wrapper for inline edit row viewer views - eliminates AnyView overhead.
public struct InlineEditRowViewerWrapper<Controller: ViewControllable>: View, Equatable {
    let controller: Controller
    let source: ItemRowModel
    let destination: ItemRowModel

    public init(controller: Controller, source: ItemRowModel, destination: ItemRowModel) {
        self.controller = controller
        self.source = source
        self.destination = destination
    }

    public var body: some View {
        controller.inlineEditRowViewer(source: source, destination: destination)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source && lhs.destination == rhs.destination
    }
}

#Preview("Inline Row Viewer Wrapper") {
    InlineEditRowViewerWrapper(
        controller: FakeViewController(),
        source: ItemRowModel(itemId: .fixture1, typeId: .none),
        destination: ItemRowModel(itemId: .fixture2, typeId: .none)
    )
}
