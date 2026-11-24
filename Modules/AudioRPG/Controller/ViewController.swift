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
        AnyView(InlineRowViewer(source: source).equatable())
    }

    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel, sourceModel: (any ModelType)?, destinationModel: (any ModelType)?) -> AnyView {
        AnyView(InlineRowViewer(source: source, sourceModel: sourceModel).equatable())
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

    /// The volume button of the game controls, for a panel of its own that shows the audio player
    /// (`audioPlayerPanel(root:)`, the game master's) or the volume slider (`volumeSlider(root:)`,
    /// a player's): it only toggles `isOpen`.
    @MainActor func volumeToggleButton(root: AudioRootModel, isOpen: Binding<Bool>) -> some View {
        PlayerVolumeButtonView(root: root, showVolume: isOpen)
    }

    /// The game master's audio player (play, skip, seek, volume), to stand in its own panel next
    /// to `volumeToggleButton(root:isOpen:)`.
#if !os(tvOS)
    @MainActor func audioPlayerPanel(root: AudioRootModel, onClose: (() -> Void)? = nil) -> some View {
        ToolbarAudioPlayerFullView(root: root, onClose: onClose)
    }
#endif

    /// The volume slider alone, to stand in its own panel next to `volumeToggleButton(root:isOpen:)`.
    @MainActor func volumeSlider(root: AudioRootModel) -> some View {
        PlayerVolumeSliderView(root: root)
    }

    /// The volume button of the game toolbar. Its popover shows the full audio player for the game
    /// master (`showsPlayer`), and only the volume slider for the players.
    @MainActor func toolbarVolumeButton(root: AudioRootModel, showsPlayer: Bool) -> some View {
        ToolbarVolumeButtonView(root: root, showsPlayer: showsPlayer)
    }
}
