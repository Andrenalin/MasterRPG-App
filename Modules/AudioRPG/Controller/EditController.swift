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

struct EditController: EditControllable {
    let itemControllable: any ItemControllable
    let fileUrlDataController: FileUrlDataController?
}

// MARK: - File Editor
extension EditController {
    func resetFile(url: URL?, in model: AudioDataModel) {
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
        let updatedFileUrl = try? await fileUrlDataController.createFileUrl(fileId: id, url: url, module: AudioDataModel.typeId.token, category: actor.category.title)
        await actor.update(url: updatedFileUrl?.rawUrl)
    }
}
