// @copyright André Trettin

import CoreRPG
import DiceRPG
import SnapshotTesting
import SwiftData
import SwiftUI
import Testing
@testable import TableRPG

@MainActor
@Suite(.serialized, .snapshots, .tags(.snapshot))
struct TableRPGDynamicPreviewSnapshotTests {
    // snapshot-root: TableRPG::DetailRootView
    @Test("DetailRootView")
    func detailRootView() async throws {
        let root = TableRootModel.preview
        let model = root.itemController.itemOrEmpty(for: TableModel.previewId)

        try await assertDynamicSnapshot("DetailRootView") {
            ManagedNavigationStack {
                DetailRootView(root: root, model: model)
                    .preferredColorScheme(.dark)
            }
        }
    }

    // snapshot-root: TableRPG::ViewerRootView
    @Test("ViewerRootView")
    func viewerRootView() async throws {
        let root = TableRootModel.preview
        let model = root.itemController.itemOrEmpty(for: TableModel.previewId)

        try await assertDynamicSnapshot("ViewerRootView") {
            ManagedNavigationStack {
                ViewerRootView(
                    model: model,
                    configuration: ViewerConfiguration(),
                    dismissAction: nil
                )
            }
        }
    }

    // snapshot-root: TableRPG::DetailFolderListView
    @Test("DetailFolderListView")
    func detailFolderListView() async throws {
        let root = TableRootModel.preview
        let model = root.itemController.itemOrEmpty(for: TableModel.previewId)

        try await assertDynamicSnapshot("DetailFolderListView") {
            DetailFolderListView(
                root: root,
                model: model,
                folderListController: root.folderListController
            )
        }
    }

    // snapshot-root: TableRPG::DetailListView
    @Test("DetailListView")
    func detailListView() async throws {
        let root = TableRootModel.preview
        let model = root.itemController.itemOrEmpty(for: TableModel.previewId)

        try await assertDynamicSnapshot("DetailListView") {
            DetailListView(
                root: root,
                model: model,
                folderListController: root.folderListController
            )
        }
    }

    private func assertDynamicSnapshot<Content: View>(
        _ name: String,
        @ViewBuilder content: () -> Content
    ) async throws {
        let container = try await TableRPGDynamicPreviewSnapshotFixtureCache.modelContainer()
        assertRepositorySnapshot(
            of: content()
                .modifier(MockRootViewModifier(modelContext: container.mainContext))
                .modelContainer(container)
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

@MainActor
private enum TableRPGDynamicPreviewSnapshotFixtureCache {
    private static var cachedContainer: ModelContainer?

    static func modelContainer() async throws -> ModelContainer {
        if let cachedContainer {
            return cachedContainer
        }
        let container = try await MockData.makeSharedContext()
        cachedContainer = container
        return container
    }
}
