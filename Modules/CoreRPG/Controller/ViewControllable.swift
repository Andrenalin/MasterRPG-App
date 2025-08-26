// @copyright André Trettin

import Foundation
import SwiftData
import SwiftUI

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
    var goupViewType: GroupViewType { get }
    var thumbnailRowViewType: ThumbnailRowViewType { get }
    
    func thumbnailRowView(for itemId: UUID) -> AnyView
}

public extension ViewControllable {
    func thumbnailRowView(for itemId: UUID) -> AnyView { AnyView(EmptyView()) }
}
