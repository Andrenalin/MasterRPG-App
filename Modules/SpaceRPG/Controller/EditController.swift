// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
internal import AppKit
#else
internal import UIKit
#endif

struct EditController {
    let fileUrlDataController: FileUrlDataController?
}

extension EditController: EditControllable {
    typealias Model = SpaceDataModel
}

// MARK: - Edit Data Model Properties
extension EditController {
    func createNewEntry(in model: SpaceDataModel, childId: UUID) -> SpaceEntryDataModel {
        SpaceEntryDataModel(id: UUID(), index: Int16(model.entries.count), parentId: model.id, childId: childId, item: model)
    }
    
    func duplicate(model: SpaceDataModel) {
        let newId = UUID()
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            let fileUrl = try? await fileUrlDataController?.duplicate(fileUrl: actor.fileUrl, for: newId)
            await actor.duplicate(newId: newId, url: fileUrl?.rawUrl)
            await actor.save()
        }
    }
}

// MARK: - File editor
extension EditController {
    func resetFile(url: URL?, in model: SpaceDataModel) {
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            await resetFile(url: url, id: id, actor: actor)
            await actor.save()
        }
    }

    private func resetFile(url: URL?, id: UUID, actor: DataModelActor) async {
        guard let fileUrlDataController else { return }
        await fileUrlDataController.delete(await actor.fileUrl)
        guard let url else {
            await actor.update(url: url)
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        if await actor.name.isEmpty {
            let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            let name = url.lastPathComponent.replacingOccurrences(of: ext, with: "")
            await actor.update(name: name)
        }
        let updatedFileUrl = try? await fileUrlDataController.createFileUrl(fileId: id, url: url, module: SpaceDataModel.typeId.token, category: actor.category.title)
        await actor.update(url: updatedFileUrl?.rawUrl)
    }
}
