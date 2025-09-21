// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public protocol LinkDataTransferable: Sendable, Codable, Transferable {
    var module: NetworkModules { get }
    var itemId: UUID { get }
    var entryId: UUID? { get }
    var name: String { get }
}

extension LinkDataTransferable {
    var linkRepresentation: String {
        if let entryId {
            return "[\(name)](\(URL.appScheme)://\(module.token)/0/\(itemId)/\(entryId)"
        } else {
            return "[\(name)](\(URL.appScheme)://\(module.token)/0/\(itemId)"
        }
    }
    
    static func linkDataType(module: NetworkModules) -> any LinkDataTransferable {
        switch module {
        case .adventure: LinkAdventureData(itemId: UUID(), name: "")
        case .audio: LinkAudioData(itemId: UUID(), name: "")
        case .value: LinkCharacterData(itemId: UUID(), name: "")
        case .dice: LinkDiceData(itemId: UUID(), name: "")
        case .map: LinkMapData(itemId: UUID(), name: "")
        case .pdf: LinkPdfData(itemId: UUID(), name: "")
        case .photo: LinkPhotoData(itemId: UUID(), name: "")
        case .space: LinkSpaceData(itemId: UUID(), name: "")
        case .table: LinkTableData(itemId: UUID(), name: "")
        case .weather: LinkWeatherData(itemId: UUID(), name: "")
        default: LinkAdventureData(itemId: UUID(), name: "")
        }
    }
}

extension UTType {
    public static var adventureLink: UTType { UTType(exportedAs: "de.andretrettin.MasterRPG.Link.Adventure") }
    public static var audioLink: UTType { UTType(exportedAs: "de.andretrettin.MasterRPG.Link.Audio") }
    public static var characterLink: UTType { UTType(exportedAs: "de.andretrettin.MasterRPG.Link.Character") }
    public static var diceLink: UTType { UTType(exportedAs: "de.andretrettin.MasterRPG.Link.Dice") }
    public static var mapLink: UTType { UTType(exportedAs: "de.andretrettin.MasterRPG.Link.Map") }
    public static var pdfLink: UTType { UTType(exportedAs: "de.andretrettin.MasterRPG.Link.Pdf") }
    public static var photoLink: UTType { UTType(exportedAs: "de.andretrettin.MasterRPG.Link.Photo") }
    public static var spaceLink: UTType { UTType(exportedAs: "de.andretrettin.MasterRPG.Link.Space") }
    public static var tableLink: UTType { UTType(exportedAs: "de.andretrettin.MasterRPG.Link.Table") }
    public static var weatherLink: UTType { UTType(exportedAs: "de.andretrettin.MasterRPG.Link.Weather") }
}

public struct LinkAdventureData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .adventureLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .adventure }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkAudioData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .audioLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .audio }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkCharacterData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .characterLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .value }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkDiceData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .diceLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .dice }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkMapData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .mapLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .map }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkPdfData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pdfLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .pdf }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkPhotoData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .photoLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .photo }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkSpaceData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .spaceLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .space }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkTableData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tableLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .table }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}

public struct LinkWeatherData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .weatherLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules { .weather }
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
}
