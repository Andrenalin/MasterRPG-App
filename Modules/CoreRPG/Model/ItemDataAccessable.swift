// @copyright André Trettin

import Foundation

public protocol EntryDataAccessable {
    var id: UUID { get }
    var name: String { get }
}

public protocol ItemDataAccessable {
    associatedtype Entry: EntryDataAccessable, Identifiable, Equatable
    
    static var typeId: NetworkModules { get }

    var id: UUID { get }
    var name: String { get set }
    var category: ItemListCategory { get set }
    var information: String { get set }
    var tags: [String] { get set }
    var displayState: Int { get }
    var entries: [Entry]? { get set }

    subscript(id: UUID) -> Entry { get set }

    func urlAdr(linkNumber: Int) -> String
    func urlAdr(linkNumber: Int, entryId: UUID) -> String
    func urlName() -> String
    func urlName(entryId: UUID) -> String
    func url(linkNumber: Int) -> String
    func url(linkNumber: Int, entryId: UUID) -> String
}

public extension ItemDataAccessable {
    var isHidden: Bool {
        displayState == DisplayStateMask.totalHidden.rawValue
    }

    var isGroupHidden: Bool {
        (displayState & DisplayStateMask.groupHidden.rawValue) > 0
    }

    var hideName: Bool {
        (displayState & DisplayStateMask.nameHidden.rawValue) > 0
    }

    var hideDescription: Bool {
        (displayState & DisplayStateMask.descriptionHidden.rawValue) > 0
    }

    var hideOther: Bool {
        (displayState & DisplayStateMask.otherHidden.rawValue) > 0
    }
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
