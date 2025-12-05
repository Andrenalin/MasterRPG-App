// @copyright André Trettin

import Foundation
import SwiftUI

public protocol EntryDataAccessable {
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
}

public extension EntryDataAccessable {
    func filter(with search: String) -> Bool {
        name.localizedCaseInsensitiveContains(search)
    }
    
    func filter(_ text: String, selectedTags: [TagFilterSelection]) -> Bool {
        filter(with: text) || !(selectedTags.map { $0.tag }.filter { filter(with: $0) }.isEmpty)
    }

    func linkContent() -> String { name }
    
    var isGroupHidden: Bool {
        (displayState & DisplayStateMask.groupHidden.rawValue) > 0
    }
}

public struct EmtpyEntryViewModel: EntryDataAccessable, Identifiable, Equatable, Sendable {
    public static let empty: EmtpyEntryViewModel = EmtpyEntryViewModel()
    public static func newChild(id: UUID) -> EmtpyEntryViewModel {
        EmtpyEntryViewModel(childId: id)
    }

    public var id: UUID = UUID()
    public var childId: UUID = UUID()
    public var name: String = ""
    public var content: String = ""
    public var displayState: Int = 0
    
    public func duplicate() -> EmtpyEntryViewModel {
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
