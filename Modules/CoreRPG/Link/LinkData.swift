// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public typealias LinkDataTypes = Codable & Transferable

public struct LinkData: Codable, Transferable {
    public init(itemId: UUID, entryId: UUID? = nil, module: NetworkModules, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.module = module
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: LinkData.self, contentType: .text)
        ProxyRepresentation(exporting: \.name)
    }

    public let itemId: UUID
    public let entryId: UUID?
    public let module: NetworkModules
    public let name: String
    
    static func linkData(for module: NetworkModules, itemId: UUID, entryId: UUID?, name: String) -> any LinkDataTypes {
        switch module {
        case .dice:
            LinkDiceData(itemId: itemId, name: name)
        default:
            LinkData(itemId: itemId, entryId: entryId, module: module, name: name)
        }
    }
}


public struct LinkDiceData: Codable, Transferable {
    public init(itemId: UUID, name: String) {
        self.itemId = itemId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .dice)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public let itemId: UUID
    public let name: String
    
    var linkRepresentation: String {
        "[\(name)](\(URL.appScheme)://\(NetworkModules.dice.token)/0/\(itemId)"
    }
}

extension UTType {
    static var dice: UTType { UTType(exportedAs: "de.andretrettin.MasterRPG.Link.Dice") }
}

extension View {
    func draggable(for module: NetworkModules, itemId: UUID, entryId: UUID?, name: String) -> some View {
        modifier(LinkDragViewModifier(itemId: itemId, entryId: entryId, module: module, name: name))
    }
}

struct LinkDragViewModifier: ViewModifier {
    let itemId: UUID
    let entryId: UUID?
    let module: NetworkModules
    let name: String

    func body(content: Content) -> some View {
        switch module {
        case .dice:
            content.draggable(LinkDiceData(itemId: itemId, name: name))
        default:
            content.draggable(LinkData(itemId: itemId, entryId: entryId, module: module, name: name))
        }
    }
}
