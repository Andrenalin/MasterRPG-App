// © André Trettin

import Foundation
import SwiftData

@MainActor @Observable
public final class LinkRootController {
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
        
        self.linkRegisterController = LinkRegisterController(container: container)
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
    
    private let linkRegisterController: LinkRegisterController
}

extension LinkRootController {
    public func handleTextLink(url: URL, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) -> Void)?, editAction: ((LinkDataModel) -> Bool)?) -> String {
        guard let linkId = url.linkId, let model = linkRegisterController.linkDataModel(linkId: linkId) else { return text }
        
        guard let brokenLink = brokenTextLinkToggle(url: url, model: model, in: text) else {
            let controller = linkController(for: model.destinationModule)
            return controller.toggleTextLink(model: model, command: url.linkCommand, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        }
        return brokenLink
    }
}

extension LinkRootController: LinkControllable {
    public var itemControllable: ItemControllable {
        adventureRoot.itemControllable
    }
    
//    public func toggleTextLink(model: LinkDataModel, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
//        linkController(for: model.destinationModule).toggleTextLink(model: model, command: command, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
//    }

    public func toggleSheet(itemId: UUID, level: Int, module: NetworkModules) -> SheetModel? {
        linkController(for: module).toggleSheet(itemId: itemId, level: level, module: module)
    }
}

private extension LinkRootController {
    func linkController(for module: NetworkModules) -> LinkControllable {
        switch module {
        case .audio: audioRoot.linkControllable
        case .value: characterRoot.linkControllable
        case .dice: diceRoot.linkControllable
        case .map: mapRoot.linkControllable
        case .pdf: pdfRoot.linkControllable
        case .photo: photoRoot.linkControllable
        case .space: spaceRoot.linkControllable
        case .table: tableRoot.linkControllable
        case .weather: weatherRoot.linkControllable
        case .adventure: adventureRoot.linkControllable
        default: adventureRoot.linkControllable
        }
    }
    
    func brokenTextLinkToggle(url: URL, model: LinkDataModel, in text: String) -> String? {
        guard !validateLink(model: model) else { return nil }
        return text.toggleLink(url: url.absoluteString, with: "🚨 \(String(localized: model.sourceModule.localizedTitle)) Link is broken")
    }

    func validateLink(model: LinkDataModel) -> Bool {
        let controller = linkController(for: model.sourceModule)
        return controller.validate(itemId: model.sourceId, entryId: model.sourceEntryId)
    }
}

extension LinkRootController {
    /// Scans the given text for links of the form `[name](SCHEME://UUID/COMMAND)` and `[name](SCHEME://UUID)`, then fetches matching LinkDataModel rows by ID.
    /// - Parameters:
    ///   - text: The text to scan.
    /// - Returns: All LinkDataModel instances whose `id` is referenced in the text.
    func links(in text: String) -> [LinkReplaceModel] {
        let registerController = LinkRegisterController(container: container)
        let links = ReferenceScanner.parseUrlsUuid(for: URL.appScheme, in: text)
        return links.compactMap { rawLink -> LinkReplaceModel? in
            guard let link = registerController.linkDataModel(linkId: rawLink.linkId) else { return nil }
            let markDown = rawLink.markDown(for: URL.appScheme)
            let range = text.range(of: markDown) ?? text.startIndex..<text.endIndex
            let command = rawLink.command
            return LinkReplaceModel(name: rawLink.name, module: link.sourceModule, linkNumber: 0, itemId: link.sourceId, entryId: link.sourceEntryId, markDown: markDown, command: command, range: range)
        }
    }
}
