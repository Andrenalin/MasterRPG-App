// @copyright André Trettin

import CoreRPG
import SnapshotTesting
import SwiftData
import SwiftUI
import Testing
@testable import AudioRPG

@MainActor
@Suite(.serialized, .snapshots, .tags(.snapshot))
struct AudioRPGDynamicPreviewSnapshotTests {
    // snapshot-root: AudioRPG::AudioPlayerPlaybackControls
    @Test("AudioPlayerPlaybackControls")
    func audioPlayerPlaybackControls() async throws {
        try await assertPreviewSnapshot("AudioPlayerPlaybackControls") { root in
            AudioPlayerPlaybackControls(audioPlayerModel: root.audioPlayerModel)
            .padding()
        }
    }

    // snapshot-root: AudioRPG::AudioPlayerTimelineView
    @Test("AudioPlayerTimelineView")
    func audioPlayerTimelineView() async throws {
        try await assertPreviewSnapshot("AudioPlayerTimelineView") { root in
            AudioPlayerTimelineView(
                currentItem: root.audioPlayerModel.currentItem,
                audioPlayerModel: root.audioPlayerModel,
                viewModel: AudioPlayerBarViewModel()
            )
            .padding()
        }
    }

    // snapshot-root: AudioRPG::AudioPlayerVolumeControl
    @Test("AudioPlayerVolumeControl")
    func audioPlayerVolumeControl() async throws {
        try await assertPreviewSnapshot("AudioPlayerVolumeControl") { root in
            AudioPlayerVolumeControl(
                audioPlayerModel: root.audioPlayerModel,
                isSliderVisible: .constant(true),
                onToggleMute: {}
            )
            .padding()
        }
    }

    // snapshot-root: AudioRPG::PlayListView
    @Test("PlayListView")
    func playListView() async throws {
        try await assertPreviewSnapshot("PlayListView") { root in
            PlayListView(root: root)
                .padding()
        }
    }

    // snapshot-root: AudioRPG::DetailRootView
    @Test("DetailRootView")
    func detailRootView() async throws {
        try await assertPreviewSnapshot("DetailRootView") { root in
            ManagedNavigationStack {
                DetailRootView(
                    root: root,
                    model: root.itemController.itemOrEmpty(for: AudioModel.previewId)
                )
                .preferredColorScheme(.dark)
            }
        }
    }

    // snapshot-root: AudioRPG::ViewerRootView
    @Test("ViewerRootView")
    func viewerRootView() async throws {
        try await assertPreviewSnapshot("ViewerRootView") { root in
            ManagedNavigationStack {
                ViewerRootView(
                    model: root.itemController.itemOrEmpty(for: AudioModel.previewId),
                    configuration: ViewerConfiguration(closeButton: true),
                    dismissAction: nil
                )
            }
        }
    }

    // snapshot-root: AudioRPG::PlayToolbarButton
    @Test("PlayToolbarButton")
    func playToolbarButton() async throws {
        try await assertPreviewSnapshot("PlayToolbarButton") { root in
            PlayToolbarButton(
                root: root,
                model: root.itemController.itemOrEmpty(for: AudioModel.previewId)
            )
            .padding()
        }
    }

    // snapshot-root: AudioRPG::DetailEditorView
    @Test("DetailEditorView")
    func detailEditorView() async throws {
        try await assertPreviewSnapshot("DetailEditorView") { root in
            DetailEditorView(
                root: root,
                model: root.itemController.itemOrEmpty(for: AudioModel.previewId)
            )
        }
    }

    // snapshot-root: AudioRPG::DetailFolderListView
    @Test("DetailFolderListView")
    func detailFolderListView() async throws {
        try await assertPreviewSnapshot("DetailFolderListView") { root in
            DetailFolderListView(
                root: root,
                model: root.itemController.itemOrEmpty(for: AudioModel.previewId),
                folderListController: root.folderListController
            )
        }
    }

    // snapshot-root: AudioRPG::DetailListView
    @Test("DetailListView")
    func detailListView() async throws {
        try await assertPreviewSnapshot("DetailListView") { root in
            DetailListView(
                root: root,
                model: root.itemController.itemOrEmpty(for: AudioModel.previewId),
                folderListController: root.folderListController
            )
        }
    }

    private func assertPreviewSnapshot<Content: View>(
        _ name: String,
        @ViewBuilder content: (AudioRootModel) -> Content
    ) async throws {
        let root = AudioRootModel.previewFixture()
        let container = try await MockData.makeSharedContext()

        assertRepositorySnapshot(
            of: content(root)
                .environment(root)
                .environment(AppGameStateModel())
                .environment(AppWindowSizeModel())
                .environment(AppFocusModel())
                .environment(SearchBarVisibleModel())
                .environment(CacheItemListModel())
                .environment(ScenesManager())
                .modifier(MockRootViewModifier())
                .modelContainer(container)
                .moduleTint(root.configurable.module)
                .deterministicSnapshotEnvironment()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background),
            as: .image(
                perceptualPrecision: 0.98,
                layout: .fixed(width: 390, height: 844)
            ),
            named: name
        )
    }
}
