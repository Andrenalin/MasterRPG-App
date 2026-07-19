// @copyright André Trettin

import CoreRPG
import SnapshotTesting
import SwiftData
import SwiftUI
import Testing
@testable import AdventureRPG

@MainActor
@Suite(.disabled(if: SnapshotTestAvailability.isDisabledForCurrentXcode, "Snapshot tests are disabled on Xcode 26."), .serialized, .snapshots, .tags(.snapshot))
struct AdventureRPGDynamicPreviewSnapshotTests {
    // snapshot-root: AdventureRPG::DetailRootView
    @Test("DetailRootView")
    func detailRootView() async throws {
        try await assertPreviewSnapshot("DetailRootView") { root in
            ManagedNavigationStack {
                DetailRootView(
                    root: root,
                    model: root.itemController.itemOrEmpty(for: AdventureModel.previewId)
                )
                .preferredColorScheme(.dark)
            }
        }
    }

    // snapshot-root: AdventureRPG::DetailFolderListView
    @Test("DetailFolderListView")
    func detailFolderListView() async throws {
        try await assertPreviewSnapshot("DetailFolderListView") { root in
            DetailFolderListView(
                root: root,
                model: root.itemController.itemOrEmpty(for: AdventureModel.previewId),
                folderListController: root.folderListController
            )
        }
    }

    // snapshot-root: AdventureRPG::DetailListView
    @Test("DetailListView")
    func detailListView() async throws {
        try await assertPreviewSnapshot("DetailListView") { root in
            DetailListView(
                root: root,
                model: root.itemController.itemOrEmpty(for: AdventureModel.previewId),
                folderListController: root.folderListController
            )
        }
    }

    private func assertPreviewSnapshot<Content: View>(
        _ name: String,
        @ViewBuilder content: (AdventureRootModel) -> Content
    ) async throws {
        let root = AdventureRootModel.previewFixture()
        let container = try await MockData.makeSharedContext()

        assertRepositorySnapshot(
            of: content(root)
                .environment(root)
                .environment(AppGameStateModel())
                .environment(AppWindowSizeModel())
                .environment(CacheItemListModel())
                .environment(ScenesManager())
                .environment(root.audioRoot)
                .environment(root.characterRoot)
                .environment(root.diceRoot)
                .environment(root.mapRoot)
                .environment(root.pdfRoot)
                .environment(root.photoRoot)
                .environment(root.spaceRoot)
                .environment(root.tableRoot)
                .environment(root.weatherRoot)
                .modifier(MockRootViewModifier())
                .modelContainer(container)
                .tint(root.configurable.module.tint)
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
