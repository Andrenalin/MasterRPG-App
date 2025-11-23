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

public enum ThumbnailRowViewType: Hashable, Sendable {
    case none
    case photo
    case custom
}

public protocol ViewControllable: Sendable {
    var fileImporterViewType: FileImporterViewType { get }
    var goupViewType: GroupViewType { get }
    var thumbnailRowViewType: ThumbnailRowViewType { get }
    
    @MainActor func fileImporterView(for itemId: UUID, preopen: Bool, layoutDown: Bool) -> AnyView
    func thumbnailRowView(for itemId: UUID) -> AnyView
}

public extension ViewControllable {
    var fileImporterViewType: FileImporterViewType { .file }
    
    @MainActor func fileImporterView(for itemId: UUID, preopen: Bool, layoutDown: Bool) -> AnyView { AnyView(EmptyView()) }
    func thumbnailRowView(for itemId: UUID) -> AnyView { AnyView(EmptyView()) }
}
