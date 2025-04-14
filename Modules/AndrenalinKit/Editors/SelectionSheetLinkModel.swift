// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor @Observable
public final class SelectionSheetLinkModel: Sendable {
    public init(selection: Bool = false, selectionView: AnyView? = nil) {
        self.selection = selection
        self.selectionView = selectionView
    }
    
    public var selection: Bool = false
    public var selectionFullScreen: Bool = false
    @ObservationIgnored
    public var idealSize: CGSize?
    @ObservationIgnored
    public var selectionView: AnyView?
    @ObservationIgnored
    public var selectionFullView: AnyView?
    public var entryId: UUID = UUID()
    @ObservationIgnored
    public var dismissedAction: (@MainActor @Sendable () -> Void)? = nil
    public var dismissedFullAction: (@MainActor @Sendable () -> Void)? = nil
    public var childId: UUID?
    public var generatorId: UUID?
}
