// @copyright André Trettin

import Foundation
import SwiftUI

public enum FileImporterViewType: Hashable, Sendable {
    case file
    case custom
}

public enum GroupViewType: Hashable, Sendable {
    case none
    case item
    case photo
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

public protocol ViewControllable: Sendable {
    var fileImporterViewType: FileImporterViewType { get }
    var goupViewType: GroupViewType { get }
    var sharingViewType: SharingViewType { get }
    var thumbnailRowViewType: ThumbnailRowViewType { get }
        
    @MainActor func fileImporterView(for itemId: UUID, preopen: Bool, layoutDown: Bool) -> AnyView
    @MainActor func sharingView(for itemId: UUID) -> AnyView
    @MainActor func thumbnailRowView(for itemId: UUID) -> AnyView
}

public extension ViewControllable {
    var fileImporterViewType: FileImporterViewType { .file }
    @MainActor func fileImporterView(for itemId: UUID, preopen: Bool, layoutDown: Bool) -> AnyView { AnyView(EmptyView()) }
    
    var sharingViewType: SharingViewType { .none }
    @MainActor func sharingView(for itemId: UUID) -> AnyView { AnyView(EmptyView()) }

    @MainActor func thumbnailRowView(for itemId: UUID) -> AnyView { AnyView(EmptyView()) }
    
    @MainActor func linkListView(rootController: ItemRootController, type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> AnyView {
        AnyView(
        LinkItemRootView(root: rootController, type: type)
            .environment(rootController)
            .environment(itemSelectionModel)
        )
    }

}
