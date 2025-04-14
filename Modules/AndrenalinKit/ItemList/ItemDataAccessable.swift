// @copyright André Trettin

import Foundation
import SwiftUI

public protocol ItemDataAccessable {
    associatedtype Entry: EntryDataAccessable, Identifiable, Equatable

    static var empty: Self { get }
    static var typeId: NetworkModules { get }
    static func empty(_ id: UUID) -> Self
    
    var id: UUID { get }
    var name: String { get set }
    var category: ItemListCategory { get set }
    var description: String { get set }
    var tags: [String] { get set }
    var displayState: Int { get set }
    var isGroupHidden: Bool { get }
    var isGroupHiddenToggle: Bool { get set }
    var entries: [Entry] { get set }

    subscript(id: UUID) -> Entry { get set }

    func urlAdr(linkNumber: Int) -> String
    func urlAdr(linkNumber: Int, entryId: UUID) -> String
    func urlName() -> String
    func urlName(entryId: UUID) -> String
    func url(linkNumber: Int) -> String
    func url(linkNumber: Int, entryId: UUID) -> String

    func copy() -> Self
    func duplicate() -> Self
    func filter(_ filter: String) -> Bool
    func isEqual(other: Self) -> Bool
    func replace(with model: Self) -> Bool
}

public extension ItemDataAccessable {
    func urlAdr(linkNumber: Int) -> String {
        "\(URL.appScheme)://\(Self.typeId.token)/\(linkNumber)/\(id)"
    }

    func urlAdr(linkNumber: Int, entryId: UUID) -> String {
        "\(urlAdr(linkNumber: linkNumber))/\(entryId)"
    }

    func urlName() -> String {
        name.withoutLink()
    }

    func urlName(entryId: UUID) -> String {
        self[entryId].name.withoutLink()
    }

    func url(linkNumber: Int) -> String {
        "[\(urlName())](\(urlAdr(linkNumber: linkNumber)))"
    }

    func url(linkNumber: Int, entryId: UUID) -> String {
        "[\(urlName(entryId: entryId))](\(urlAdr(linkNumber: linkNumber, entryId: entryId)))"
    }
}
