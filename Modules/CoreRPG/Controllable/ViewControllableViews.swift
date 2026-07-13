// @copyright André Trettin

import Foundation
import SwiftUI

/// Wrapper views that avoid AnyView type erasure while maintaining protocol flexibility
/// These views cache and optimize the view rendering from ViewControllable

/// Optimized wrapper for file importer views - eliminates AnyView overhead
public struct FileImporterViewWrapper<Controller: ViewControllable>: View {
    let controller: Controller
    let itemId: UUID
    let preopen: Bool
    let layoutDown: Bool

    public init(controller: Controller, itemId: UUID, preopen: Bool, layoutDown: Bool) {
        self.controller = controller
        self.itemId = itemId
        self.preopen = preopen
        self.layoutDown = layoutDown
    }

    public var body: some View {
        controller.fileImporterView(for: itemId, preopen: preopen, layoutDown: layoutDown)
    }
}

/// Optimized wrapper for sharing views - eliminates AnyView overhead
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

/// Optimized wrapper for thumbnail row views - eliminates AnyView overhead
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

/// Optimized wrapper for row viewer views - eliminates AnyView overhead
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

/// Optimized wrapper for inline edit row viewer views - eliminates AnyView overhead
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

/// Optimized wrapper for link list views - eliminates AnyView overhead
public struct LinkListViewWrapper<Controller: ViewControllable>: View {
    let controller: Controller
    let rootController: ItemRootController
    let type: LinkRootType
    let itemSelectionModel: ItemSelectionModel

    public init(controller: Controller, rootController: ItemRootController, type: LinkRootType, itemSelectionModel: ItemSelectionModel) {
        self.controller = controller
        self.rootController = rootController
        self.type = type
        self.itemSelectionModel = itemSelectionModel
    }

    public var body: some View {
        controller.linkListView(rootController: rootController, type: type, itemSelectionModel: itemSelectionModel)
    }
}

#Preview("File Importer Wrapper") {
    FileImporterViewWrapper(controller: FakeViewController(), itemId: UUID(), preopen: false, layoutDown: false)
}

#Preview("Sharing Wrapper") {
    SharingViewWrapper(controller: FakeViewController(), itemId: UUID())
}

#Preview("Thumbnail Wrapper") {
    ThumbnailRowViewWrapper(controller: FakeViewController(), itemId: UUID())
}

#Preview("Row Viewer Wrapper") {
    RowViewerWrapper(
        controller: FakeViewController(),
        source: ItemRowModel(itemId: UUID(), typeId: .none),
        destination: ItemRowModel(itemId: UUID(), typeId: .none)
    )
}

#Preview("Inline Row Viewer Wrapper") {
    InlineEditRowViewerWrapper(
        controller: FakeViewController(),
        source: ItemRowModel(itemId: UUID(), typeId: .none),
        destination: ItemRowModel(itemId: UUID(), typeId: .none)
    )
}

#Preview("Link List Wrapper") {
    LinkListViewWrapper(
        controller: FakeViewController(),
        rootController: ItemRootController.fake,
        type: .inspector,
        itemSelectionModel: ItemSelectionModel()
    )
}
