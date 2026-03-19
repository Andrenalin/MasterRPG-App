// @copyright André Trettin

import CoreRPG
import Observation
import SwiftUI

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .none
    public let sharingViewType: SharingViewType = .custom
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {
    @MainActor public func sharingView(for itemId: UUID) -> AnyView {
        AnyView(SharingActionView(itemId: itemId, showPlayControl: false).equatable())
    }
    
    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination).equatable())
    }
}

// MARK: - New Views

public extension ViewController {
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type)
            .environment(itemSelectionModel)
    }

    @MainActor func inlineViewer(root: AudioRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
//        Task {
//            let list = root.itemController.audioList(itemId: id)
//            await root.audioController.add(audio: list, replace: true)
//            root.audioController.togglePlay(id: list.first?.id)
//        }
//        return AudioPlayerBarView()
        let model = root.itemController.itemOrEmpty(for: id)
        return DetailRootView(root: root, model: model)
            .environment(root)
    }

    @MainActor func gameView(root: AudioRootModel) -> some View {
        LinkRootView(type: .inspector)
            .environment(ItemSelectionModel())
    }
}

// MARK: - Others

public extension ViewController {
    @MainActor
    func viewAudioPlayer(root: AudioRootModel, with id: UUID?) -> some View {
        root.gameController.play(id: id, shouldPlay: true)
        return AudioPlayerView()
            .environment(root)
    }

    func viewVolume(root: AudioRootModel, alignment: Alignment) -> some View {
        PlayerVolumeView(root: root, alignment: alignment)
    }
}
