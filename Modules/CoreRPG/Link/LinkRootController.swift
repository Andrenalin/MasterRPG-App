// © André Trettin

import Foundation
import SwiftData

@MainActor @Observable
public final class LinkRootController {
    public init(container: ModelContainer, root: RootManager) {
        self.container = container
        self.root = root
        self.linkRegisterController = LinkRegisterController(container: container)
    }

    @ObservationIgnored let container: ModelContainer
    public let module: NetworkModules = .none
    @ObservationIgnored let root: RootManager
    public let linkRegisterController: LinkRegisterController
}

public extension LinkRootController {
    func handleTextLink(url: URL, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) -> Void)?, editAction: ((LinkDataModel) -> Bool)?) -> String {
        guard let linkId = url.linkId, let model = linkRegisterController.linkDataModel(linkId: linkId) else { return text }
        
        guard let brokenLink = brokenTextLinkToggle(url: url, model: model, in: text) else {
            let controller = linkController(for: model.sourceModule)
            return controller.toggleTextLink(model: model, command: url.linkCommand, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        }
        return brokenLink
    }
}

extension LinkRootController: LinkControllable {
    public var itemControllable: ItemControllable {
        root[.adventure]!.itemControllable
    }
    
    @MainActor public func remove(linkModel: LinkDataModel) {
        linkController(for: linkModel.destinationModule).remove(linkModel: linkModel)
        linkRegisterController.remove(linkId: linkModel.id)
    }

    public func toggleSheet(itemId: UUID, level: Int, module: NetworkModules) -> SheetModel? {
        linkController(for: module).toggleSheet(itemId: itemId, level: level, module: module)
    }
}

private extension LinkRootController {
    func linkController(for module: NetworkModules) -> LinkControllable {
        root[module]!.linkControllable
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
