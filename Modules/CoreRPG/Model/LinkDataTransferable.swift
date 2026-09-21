// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public protocol LinkDataTransferable: Sendable, Codable, Transferable {
    var module: NetworkModules { get }
    var itemId: UUID { get }
    var entryId: UUID? { get }
    var name: String { get }
    var isMove: Bool { get }
}

extension LinkDataTransferable {
    public var linkRepresentation: String {
        LinkBuilder.markdown(name: name, module: module, itemId: itemId, entryId: entryId)
    }
    
    static func linkDataType(module: NetworkModules) -> any LinkDataTransferable {
        switch module {
        case .adventure: LinkAdventureData(itemId: UUID(), name: "")
        case .audio: LinkAudioData(itemId: UUID(), name: "")
        case .value: LinkCharacterData(itemId: UUID(), name: "")
        case .dice: LinkDiceData(itemId: UUID(), name: "")
        case .editor: LinkEntryData(itemId: UUID(), name: "", module: module)
        case .map: LinkMapData(itemId: UUID(), name: "")
        case .pdf: LinkPdfData(itemId: UUID(), name: "")
        case .photo: LinkPhotoData(itemId: UUID(), name: "")
        case .rule: LinkRuleData(itemId: UUID(), name: "")
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
    public static var ruleLink: UTType { UTType(exportedAs: "de.andretrettin.MasterRPG.Link.Rule") }
    public static var spaceLink: UTType { UTType(exportedAs: "de.andretrettin.MasterRPG.Link.Space") }
    public static var tableLink: UTType { UTType(exportedAs: "de.andretrettin.MasterRPG.Link.Table") }
    public static var weatherLink: UTType { UTType(exportedAs: "de.andretrettin.MasterRPG.Link.Weather") }
    
    public static var entryLink: UTType { UTType(exportedAs: "de.andretrettin.MasterRPG.Link.Entry") }
}

/// Empty link transferable for modules that don't support entry editor
public struct EmptyLinkTransferable: LinkDataTransferable {
    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool
    
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

public struct LinkEntryData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String, module: NetworkModules, isMove: Bool = false) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
        self.module = module
        self.isMove = isMove
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .entryLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool
}

public struct LinkAdventureData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String, module: NetworkModules = .adventure, isMove: Bool = false) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
        self.module = .adventure
        self.isMove = isMove
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .adventureLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool
}

public struct LinkAudioData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String, module: NetworkModules = .audio, isMove: Bool = false) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
        self.module = .audio
        self.isMove = isMove
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .audioLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool
}

public struct LinkCharacterData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String, module: NetworkModules = .value, isMove: Bool = false) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
        self.module = .value
        self.isMove = isMove
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .characterLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool
}

public struct LinkDiceData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String, module: NetworkModules = .dice, isMove: Bool = false) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
        self.module = .dice
        self.isMove = isMove
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .diceLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool
}

public struct LinkMapData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String, module: NetworkModules = .map, isMove: Bool = false) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
        self.module = .map
        self.isMove = isMove
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .mapLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool
}

public struct LinkPdfData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String, module: NetworkModules = .pdf, isMove: Bool = false) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
        self.module = .pdf
        self.isMove = isMove
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pdfLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public var module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool
}

public struct LinkPhotoData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String, module: NetworkModules = .photo, isMove: Bool = false) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
        self.module = .photo
        self.isMove = isMove
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .photoLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool
}

public struct LinkSpaceData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String, module: NetworkModules = .space, isMove: Bool = false) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
        self.module = .space
        self.isMove = isMove
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .spaceLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool
}

public struct LinkRuleData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String, module: NetworkModules = .rule, isMove: Bool = false) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
        self.module = .rule
        self.isMove = isMove
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .ruleLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool
}

public struct LinkTableData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String, module: NetworkModules = .table, isMove: Bool = false) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
        self.module = .table
        self.isMove = isMove
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tableLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool
}

public struct LinkWeatherData: LinkDataTransferable {
    public init(itemId: UUID, entryId: UUID? = nil, name: String, module: NetworkModules = .weather, isMove: Bool = false) {
        self.itemId = itemId
        self.entryId = entryId
        self.name = name
        self.module = .weather
        self.isMove = isMove
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .weatherLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }

    public let module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool
}
