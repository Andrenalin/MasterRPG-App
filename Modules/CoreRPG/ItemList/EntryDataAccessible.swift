// @copyright André Trettin

import Foundation
import SwiftUI

public protocol EntryDataAccessible {
    static var empty: Self { get }
    static func newChild(id: UUID) -> Self

    var id: UUID { get }
    var childId: UUID { get }
    var name: String { get set }
    var content: String { get set }
    var displayState: Int { get }

    func duplicate() -> Self
    func filter(with search: String) -> Bool
    func filter(_ filter: String, selectedTags: [TagFilterSelection]) -> Bool
        
    func linkContent() -> String

    /// Applies to `self` (the library's entry) what `edited` changed relative to `base`, field by
    /// field. A changed entry used to be replaced whole, which carried its session state (a
    /// Character value changed in the game) into the library and reverted fields another device
    /// changed meanwhile. The default replaces the entry; a module whose entries hold session
    /// state or several independent fields diffs them. See CODE_AUDIT_Edit_Save §5.11.
    @MainActor mutating func applyEdit(from base: Self, to edited: Self)
}

public extension EntryDataAccessible {
    func filter(with search: String) -> Bool {
        name.localizedStandardContains(search)
    }
    
    func filter(_ text: String, selectedTags: [TagFilterSelection]) -> Bool {
        filter(with: text) || !(selectedTags.map { $0.tag }.filter { filter(with: $0) }.isEmpty)
    }

    func linkContent() -> String { name }

    @MainActor mutating func applyEdit(from base: Self, to edited: Self) {
        self = edited
    }
    
    var isGroupHidden: Bool {
        (displayState & DisplayStateMask.groupHidden.rawValue) > 0
    }
}

public struct EmptyEntryViewModel: EntryDataAccessible, Identifiable, Equatable, Sendable {
    public static let empty: EmptyEntryViewModel = EmptyEntryViewModel()
    public static func newChild(id: UUID) -> EmptyEntryViewModel {
        EmptyEntryViewModel(childId: id)
    }

    public var id: UUID = UUID()
    public var childId: UUID = UUID()
    public var name: String = ""
    public var content: String = ""
    public var displayState: Int = 0
    
    public func duplicate() -> EmptyEntryViewModel {
        self
    }
    
    public func filter(with search: String) -> Bool {
        true
    }
    
    public func filter(_ text: String, selectedTags: [TagFilterSelection]) -> Bool {
        filter(with: text) || !(selectedTags.map { $0.tag }.filter { filter(with: $0) }.isEmpty)
    }
    
    public var isGroupHidden: Bool { false }
    public func linkContent() -> String { name }
}
