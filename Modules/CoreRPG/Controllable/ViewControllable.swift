// @copyright André Trettin

import Foundation
import SwiftUI

public enum FileImporterViewType: Hashable, Sendable {
    case file
    case custom
}

public enum SharingViewType: Hashable, Sendable {
    case none
    case share
    case custom
}

public enum ThumbnailRowViewType: Hashable, Sendable {
    case none
    case photo
    case custom
}

public struct ViewerConfiguration: Hashable, Sendable {
    public init(
        closeButton: Bool = false,
        addToolbar: Bool = true,
        isGame: Bool = false,
        aiExtractor: Bool = false,
        canBookmark: Bool = false
    ) {
        self.closeButton = closeButton
        self.addToolbar = addToolbar
        self.isGame = isGame
        self.aiExtractor = aiExtractor
        self.canBookmark = canBookmark
    }
    
    public let closeButton: Bool
    public let addToolbar: Bool
    public let isGame: Bool
    public let aiExtractor: Bool
    public let canBookmark: Bool
}

public protocol ViewControllable: Sendable {
    var fileImporterViewType: FileImporterViewType { get }
    var sharingViewType: SharingViewType { get }
    var thumbnailRowViewType: ThumbnailRowViewType { get }
    var supportsBatchExtraction: Bool { get }
    /// True when the module handles the space-key action itself (e.g. play, roll).
    /// When false the default behaviour — opening the file viewer — is used instead.
    var hasCustomSpaceAction: Bool { get }
    /// True when a newly created item should not auto-open the header editor (name/description).
    /// Used by file-backed modules (Audio, Pdf, Photo, Space) where the name is derived from the
    /// picked file's filename, so the user should pick a file before naming the item.
    var skipsHeaderEditorOnCreate: Bool { get }

    @MainActor func fileImporterView(for itemId: UUID, preopen: Bool, layoutDown: Bool) -> AnyView
    @MainActor func sharingView(for itemId: UUID) -> AnyView
    @MainActor func thumbnailRowView(for itemId: UUID) -> AnyView
    /// Renders the thumbnail from the passed model instead of looking it up by id.
    /// Needed when the model is not in the database yet, e.g. an imported item under review.
    @MainActor func thumbnailRowView(for model: any ItemDataAccessible) -> AnyView
    @MainActor func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView
    @MainActor func inlineEditRowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView
    /// Same as `rowViewer(source:destination:)`, but lets a caller that has
    /// already resolved `source`/`destination`'s models (typically by
    /// reading `RootManager.itemRootController(for:)?.itemControllable`
    /// once, at whatever list/`ForEach` level actually owns that
    /// subscription) hand them straight down instead of the leaf row
    /// re-resolving via `itemSync`/`itemOrEmpty` inside its own `body`.
    /// Reading `itemData` inside a per-row `body` subscribes that row to
    /// the module's *entire* `itemData` dictionary — Observation tracks a
    /// dictionary-typed property at whole-property granularity, not
    /// per-key — so editing any one item re-invalidates every other open
    /// row that resolved this way, however far down the call chain the
    /// read happened. See CODE_AUDIT_10 §8.1. Defaults to the plain
    /// 2-parameter version (ignoring both models) so conformers that don't
    /// override this keep working exactly as before.
    @MainActor func rowViewer(source: ItemRowModel, destination: ItemRowModel, sourceModel: (any ModelType)?, destinationModel: (any ModelType)?) -> AnyView
    /// Same as `rowViewer(source:destination:sourceModel:destinationModel:)`, but lets
    /// the caller tell the row whether it may offer its own share affordance — e.g. a
    /// Photo entry embedded inside a Map should never show its own share button, only
    /// the Map's. Defaults to `true` so conformers that don't override this keep
    /// working exactly as before.
    @MainActor func rowViewer(source: ItemRowModel, destination: ItemRowModel, sourceModel: (any ModelType)?, destinationModel: (any ModelType)?, isShareable: Bool) -> AnyView
    @MainActor func batchExtractionView(itemController: any ItemControllable, editController: any EditControllable, ids: [UUID]) -> AnyView?
}

public extension ViewControllable {
    var fileImporterViewType: FileImporterViewType { .file }
    @MainActor func fileImporterView(for itemId: UUID, preopen: Bool, layoutDown: Bool) -> AnyView { AnyView(EmptyView()) }

    var sharingViewType: SharingViewType { .none }
    @MainActor func sharingView(for itemId: UUID) -> AnyView { AnyView(EmptyView()) }

    @MainActor func thumbnailRowView(for itemId: UUID) -> AnyView { AnyView(EmptyView()) }
    @MainActor func thumbnailRowView(for model: any ItemDataAccessible) -> AnyView { thumbnailRowView(for: model.id) }
    @MainActor func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView { AnyView(EmptyView()) }
    @MainActor func inlineEditRowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView { AnyView(EmptyView()) }
    @MainActor func rowViewer(source: ItemRowModel, destination: ItemRowModel, sourceModel: (any ModelType)?, destinationModel: (any ModelType)?) -> AnyView {
        rowViewer(source: source, destination: destination)
    }
    @MainActor func rowViewer(source: ItemRowModel, destination: ItemRowModel, sourceModel: (any ModelType)?, destinationModel: (any ModelType)?, isShareable: Bool) -> AnyView {
        rowViewer(source: source, destination: destination, sourceModel: sourceModel, destinationModel: destinationModel)
    }

    var supportsBatchExtraction: Bool { false }
    var hasCustomSpaceAction: Bool { false }
    var skipsHeaderEditorOnCreate: Bool { false }
    @MainActor func batchExtractionView(itemController: any ItemControllable, editController: any EditControllable, ids: [UUID]) -> AnyView? { nil }

    @MainActor func linkListView(rootController: ItemRootController, type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> LinkItemRootView {
        LinkItemRootView(root: rootController, type: type, itemSelectionModel: itemSelectionModel)
    }
}
