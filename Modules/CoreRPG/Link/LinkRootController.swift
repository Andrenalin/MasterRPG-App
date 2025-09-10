// © André Trettin

import Foundation
import SwiftData

@MainActor @Observable
public final class LinkRootController: LinkControllable {
    public init(
        itemController: any ItemControllable,
        module: NetworkModules
    ) {
        self.container = itemController.container
        let fakeRoot = FakeItemRootController(itemController: itemController, module: module)
        self.adventureRoot = fakeRoot
        self.audioRoot = fakeRoot
        self.characterRoot = fakeRoot
        self.diceRoot = fakeRoot
        self.mapRoot = fakeRoot
        self.pdfRoot = fakeRoot
        self.photoRoot = fakeRoot
        self.spaceRoot = fakeRoot
        self.tableRoot = fakeRoot
        self.weatherRoot = fakeRoot
    }

    public init(
        container: ModelContainer,
        adventureRoot: any ItemRootControllable,
        audioRoot: any ItemRootControllable,
        characterRoot: any ItemRootControllable,
        diceRoot: any ItemRootControllable,
        mapRoot: any ItemRootControllable,
        pdfRoot: any ItemRootControllable,
        photoRoot: any ItemRootControllable,
        spaceRoot: any ItemRootControllable,
        tableRoot: any ItemRootControllable,
        weatherRoot: any ItemRootControllable
    ) {
        self.container = container
        self.adventureRoot = adventureRoot
        self.audioRoot = audioRoot
        self.characterRoot = characterRoot
        self.diceRoot = diceRoot
        self.mapRoot = mapRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.spaceRoot = spaceRoot
        self.tableRoot = tableRoot
        self.weatherRoot = weatherRoot
    }

    let container: ModelContainer
    public let module: NetworkModules = .none
    
    @ObservationIgnored let adventureRoot: ItemRootControllable
    @ObservationIgnored let audioRoot: ItemRootControllable
    @ObservationIgnored let characterRoot: ItemRootControllable
    @ObservationIgnored let diceRoot: ItemRootControllable
    @ObservationIgnored let mapRoot: ItemRootControllable
    @ObservationIgnored let pdfRoot: ItemRootControllable
    @ObservationIgnored let photoRoot: ItemRootControllable
    @ObservationIgnored let spaceRoot: ItemRootControllable
    @ObservationIgnored let tableRoot: ItemRootControllable
    @ObservationIgnored let weatherRoot: ItemRootControllable
}

extension LinkRootController {
    public var itemControllable: ItemControllable {
        adventureRoot.itemControllable
    }
    
    @MainActor public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        text
    }
    
    @MainActor public func generateLink(linkNumber: Int, itemId: UUID, entryId: UUID?) -> String {
        ""
    }
    
    @MainActor public func toggleSheet(itemId: UUID, level: Int, module: NetworkModules) -> SheetModel? {
        nil
    }
}

public extension LinkRootController {
    func register(link: LinkReplaceModel, destinationId: UUID, destinationEntryId: UUID? = nil, destinationModule: NetworkModules) -> UUID {
        let model = LinkDataModel(name: link.name, sourceId: link.itemId, sourceEntryId: link.entryId, sourceModule: link.module, destinationId: destinationId, destinationEntryId: destinationEntryId, destinationModel: destinationModule)
        container.mainContext.insert(model)
        try? container.mainContext.save()
        return model.id
    }

    func register(name: String = "", sourceId: UUID, sourceEntryId: UUID? = nil, sourceModule: NetworkModules, destinationId: UUID, destinationEntryId: UUID? = nil, destinationModule: NetworkModules) -> UUID {
        let model = LinkDataModel(
            name: name,
            sourceId: sourceId,
            sourceEntryId: sourceEntryId,
            sourceModule: sourceModule,
            destinationId: destinationId,
            destinationEntryId: destinationEntryId,
            destinationModel: destinationModule
        )
        container.mainContext.insert(model)
        try? container.mainContext.save()
        return model.id
    }
    
    func remove(linkId: UUID) {
        let predicate = #Predicate<LinkDataModel> {
            $0.id == linkId
        }
        let fetchDescription = FetchDescriptor<LinkDataModel>(predicate: predicate)
        let models = try? container.mainContext.fetch(fetchDescription)
        models?.forEach {
            container.mainContext.delete($0)
        }
        try? container.mainContext.save()
    }
    
    func effectedItems(targetId: UUID, targetEntryId: UUID? = nil, targetModule: NetworkModules) -> [EffectedItemModel] {
        let predicate: Predicate<LinkDataModel>
        if let targetEntryId {
            predicate = #Predicate<LinkDataModel> {
                $0.destinationId == targetId && $0.destinationEntryId == targetEntryId && $0.destinationModule == targetModule
            }
        } else {
            predicate = #Predicate<LinkDataModel> {
                $0.destinationId == targetId && $0.destinationModule == targetModule
            }
        }
        let fetchDescription = FetchDescriptor<LinkDataModel>(predicate: predicate)
        guard let models = try? container.mainContext.fetch(fetchDescription) else { return [] }
        
        return models.map {
            EffectedItemModel(id: $0.id, name: $0.name, entryName: nil, module: $0.sourceModule)
        }
    }
}

public extension LinkRootController {
    /// Scans the given text for links of the form `[name](SCHEME://UUID)`, then fetches matching LinkDataModel rows by ID.
    /// - Parameters:
    ///   - text: The text to scan.
    /// - Returns: All LinkDataModel instances whose `id` is referenced in the text.
    func links(in text: String) -> [LinkReplaceModel] {
        // Extract UUIDs using the ReferenceScanner's UUID-only parser.
        let uuidLinks = ReferenceScanner.parseUrlsUuid(for: URL.appScheme, in: text)
        let ids = uuidLinks.map { $0.linkId }
        guard !ids.isEmpty else { return [] }
        
        // Build an OR predicate over all IDs.
        // If the set is large, consider chunking to keep predicate size manageable.
        let predicates: [Predicate<LinkDataModel>] = ids.map { linkId in
            #Predicate<LinkDataModel> { $0.id == linkId }
        }
        
        let combined: Predicate<LinkDataModel> = predicates.dropFirst().reduce(predicates.first!) { partial, next in
            #Predicate<LinkDataModel> { model in
                partial.evaluate(model) || next.evaluate(model)
            }
        }
        
        let fetch = FetchDescriptor<LinkDataModel>(predicate: combined)
        let linkModels = (try? container.mainContext.fetch(fetch)) ?? []
        return linkModels.map {
            let id = $0.id
            let markDown: String
            let range: Range<String.Index>
            let command: String?
            if let link = uuidLinks.first(where: { $0.linkId == id }) {
                markDown = link.markDown(for: URL.appScheme)
                range = text.range(of: markDown) ?? text.startIndex..<text.endIndex
                command = link.command
            } else {
                markDown = self.markDown(for: $0)
                range = text.startIndex..<text.endIndex
                command = nil
            }
            return LinkReplaceModel(name: $0.name, module: $0.sourceModule, linkNumber: 0, itemId: $0.sourceId, entryId: $0.sourceEntryId, markDown: markDown, command: command, range: range)
        }
    }
    
    func markDown(for link: LinkDataModel) -> String {
        "[\(link.name)](\(URL.appScheme)://\(link.id))"
    }
}

