// @copyright André Trettin

import CoreRPG
import Observation
import os.log
import SwiftUI

public struct ViewController: Sendable {
    public let sharingViewType: SharingViewType = .custom
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
}

extension ViewController: ViewControllable {
    public var hasCustomSpaceAction: Bool { true }
    public var skipsHeaderEditorOnCreate: Bool { true }
    @MainActor public func sharingView(for itemId: UUID) -> AnyView {
        AnyView(SharingActionView(itemId: itemId, showPlayControl: false, showPlayerReport: true).equatable())
    }
    
    @MainActor public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(AudioPlayPauseButton(itemId: itemId).equatable())
    }
    
    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination).equatable())
    }

    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel, sourceModel: (any ModelType)?, destinationModel: (any ModelType)?) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination, sourceModel: sourceModel).equatable())
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
#if os(macOS)
    /// The music controls for the macOS menu bar extra (`.window` style).
    @MainActor func viewMenuBarAudioPlayer(root: AudioRootModel) -> some View {
        MenuBarAudioPlayerView()
            .environment(root)
    }
#endif

    @MainActor func viewVolume(root: AudioRootModel, alignment: Alignment) -> some View {
        PlayerVolumeView(root: root, alignment: alignment)
    }

    /// The volume button of the game toolbar. Its popover shows the full audio player for the game
    /// master (`showsPlayer`), and only the volume slider for the players.
    @MainActor func toolbarVolumeButton(root: AudioRootModel, showsPlayer: Bool) -> some View {
        ToolbarVolumeButtonView(root: root, showsPlayer: showsPlayer)
    }
}
