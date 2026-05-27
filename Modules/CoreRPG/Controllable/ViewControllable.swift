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
    public init(closeButton: Bool = false, addToolbar: Bool = true, isGame: Bool = false, aiExtractor: Bool = false, canBookmark: Bool = false) {
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

    @MainActor func fileImporterView(for itemId: UUID, preopen: Bool, layoutDown: Bool) -> AnyView
    @MainActor func sharingView(for itemId: UUID) -> AnyView
    @MainActor func thumbnailRowView(for itemId: UUID) -> AnyView
    @MainActor func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView
    @MainActor func inlineEditRowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView
    @MainActor func batchExtractionView(itemController: any ItemControllable, editController: any EditControllable, ids: [UUID]) -> AnyView?
}

public extension ViewControllable {
    var fileImporterViewType: FileImporterViewType { .file }
    @MainActor func fileImporterView(for itemId: UUID, preopen: Bool, layoutDown: Bool) -> AnyView { AnyView(EmptyView()) }

    var sharingViewType: SharingViewType { .none }
    @MainActor func sharingView(for itemId: UUID) -> AnyView { AnyView(EmptyView()) }

    @MainActor func thumbnailRowView(for itemId: UUID) -> AnyView { AnyView(EmptyView()) }
    @MainActor func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView { AnyView(EmptyView()) }
    @MainActor func inlineEditRowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView { AnyView(EmptyView()) }

    var supportsBatchExtraction: Bool { false }
    var hasCustomSpaceAction: Bool { false }
    @MainActor func batchExtractionView(itemController: any ItemControllable, editController: any EditControllable, ids: [UUID]) -> AnyView? { nil }

    @MainActor func linkListView(rootController: ItemRootController, type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> LinkItemRootView {
        LinkItemRootView(root: rootController, type: type, itemSelectionModel: itemSelectionModel)
    }
}
