// @copyright André Trettin

import CoreRPG
import Observation
import SwiftUI

public struct ViewController: Sendable {
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
        LinkRootView(type: type, itemSelectionModel: itemSelectionModel)
    }

    @MainActor func viewer(root: AudioRootModel, itemId: UUID, configuration: ViewerConfiguration, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        return ViewerRootView(model: model, configuration: configuration, dismissAction: dismissAction)
    }

    @MainActor func gameView(root: AudioRootModel) -> some View {
        LinkRootView(type: .inspector, itemSelectionModel: ItemSelectionModel())
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

    @MainActor
    func menuAudioPlayer(root: AudioRootModel, with id: UUID?) -> some View {
        root.gameController.play(id: id, shouldPlay: true)
        return AudioPlayerBarView()
            .environment(root)
    }

    func viewVolume(root: AudioRootModel, alignment: Alignment) -> some View {
        PlayerVolumeView(root: root, alignment: alignment)
    }
}
