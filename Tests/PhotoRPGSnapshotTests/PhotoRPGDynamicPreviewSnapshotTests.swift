// @copyright André Trettin

import CoreRPG
import SnapshotTesting
import SwiftData
import SwiftUI
import Testing
@testable import PhotoRPG

@MainActor
@Suite(.serialized, .snapshots, .tags(.snapshot))
struct PhotoRPGDynamicPreviewSnapshotTests {
    // snapshot-root: PhotoRPG::InlineImporterView
    @Test("InlineImporterView")
    func inlineImporterView() async throws {
        try await assertDynamicSnapshot("InlineImporterView") {
            ZStack {
                Color.blue
                InlineImporterView(
                    itemId: PhotoModel.previewId,
                    preopen: true,
                    layoutDown: true
                )
            }
        }
    }

    // snapshot-root: PhotoRPG::DetailRootView
    @Test("DetailRootView")
    func detailRootView() async throws {
        let root = PhotoRootModel.preview
        let model = root.itemController.itemOrEmpty(for: PhotoModel.previewId)

        try await assertDynamicSnapshot("DetailRootView") {
            ManagedNavigationStack {
                DetailRootView(root: root, model: model)
                    .preferredColorScheme(.dark)
            }
        }
    }

    // snapshot-root: PhotoRPG::ViewerRootView
    @Test("ViewerRootView")
    func viewerRootView() async throws {
        let root = PhotoRootModel.preview
        let model = root.itemController.itemOrEmpty(for: PhotoModel.previewId)

        try await assertDynamicSnapshot("ViewerRootView") {
            NavigationStack {
                ViewerRootView(model: model, configuration: ViewerConfiguration())
            }
        }
    }

    // snapshot-root: PhotoRPG::CarouselPhotoView
    @Test("CarouselPhotoView")
    func carouselPhotoView() async throws {
        let root = PhotoRootModel.preview
        let selections = root.itemController.itemDataModel.items.map {
            WindowItemSelection(itemId: $0)
        }

        try await assertDynamicSnapshot("CarouselPhotoView") {
            CarouselPhotoView(
                photoIds: ItemSelectionModel(
                    selection: selections,
                    isSingleSelection: false
                ),
                selection: GroupItemSelectionModel()
            )
        }
    }

    // snapshot-root: PhotoRPG::DetailFolderListView
    @Test("DetailFolderListView")
    func detailFolderListView() async throws {
        let root = PhotoRootModel.preview
        let model = root.itemController.itemOrEmpty(for: PhotoModel.previewId)

        try await assertDynamicSnapshot("DetailFolderListView") {
            DetailFolderListView(
                root: root,
                model: model,
                folderListController: root.folderListController
            )
        }
    }

    // snapshot-root: PhotoRPG::DetailListView
    @Test("DetailListView")
    func detailListView() async throws {
        let root = PhotoRootModel.preview
        let model = root.itemController.itemOrEmpty(for: PhotoModel.previewId)

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
        let container = try await PhotoRPGDynamicPreviewSnapshotFixtureCache.modelContainer()
        assertRepositorySnapshot(
            of: content()
                .modifier(MockRootViewModifier(modelContext: container.mainContext))
                .environment(AppFocusModel())
                .environment(SearchBarVisibleModel())
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
private enum PhotoRPGDynamicPreviewSnapshotFixtureCache {
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
