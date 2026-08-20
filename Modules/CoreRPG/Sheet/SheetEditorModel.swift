// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor @Observable public final class SheetEditorModel {
    public init(itemId: UUID? = nil, entryId: UUID? = nil, module: NetworkModules = .none) {
        self.itemId = itemId
        self.entryId = entryId
        self.module = module
    }
    
    public var itemId: UUID?
    public var entryId: UUID?
    public var module: NetworkModules
    public var scrollEntryId: UUID?

    public var parentModel: SheetModel?

    /// Whether `EntryEditorView` currently has an entry open for this item — i.e. its
    /// drop-link header overlay is on screen. `SheetView` uses this to disable its own
    /// row-level `.dropDestination` while that overlay is showing: on macOS 26.6 and
    /// iOS 26/27, a `.dropDestination` on an underlying row still intercepts the drag
    /// even though `.allowsHitTesting(false)` disables its taps (only macOS 27 honors
    /// `allowsHitTesting` for drop targets). Gating the row's own modifier sidesteps
    /// that OS-version-dependent hit-testing quirk instead of depending on it.
    public var isEntryEditorPresented: Bool {
        itemId != nil && entryId != nil
    }
    
    func setEdit(source: ItemRowModel) {
        self.itemId <=> source.itemId
        self.entryId <=> source.entryId
        self.module <=> source.typeId
    }
}
