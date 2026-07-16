// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SnapshotTesting
import SwiftData
import SwiftUI
import Testing
@testable import WeatherRPG

@MainActor
@Suite(.serialized, .snapshots, .tags(.snapshot))
struct WeatherRPGDynamicPreviewSnapshotTests {
    // snapshot-root: WeatherRPG::DetailRootView
    @Test("DetailRootView")
    func detailRootView() async throws {
        let root = WeatherRootModel.preview
        let model = root.itemController.itemOrEmpty(for: WeatherModel.previewId)

        try await assertDynamicSnapshot("DetailRootView") {
            ManagedNavigationStack {
                DetailRootView(root: root, model: model)
                    .preferredColorScheme(.dark)
            }
        }
    }

    // snapshot-root: WeatherRPG::ViewerRootView
    @Test("ViewerRootView")
    func viewerRootView() async throws {
        let root = WeatherRootModel.preview
        let model = root.itemController.itemOrEmpty(for: WeatherModel.previewId)

        try await assertDynamicSnapshot("ViewerRootView") {
            ViewerRootView(model: model, configuration: ViewerConfiguration())
        }
    }

    // snapshot-root: WeatherRPG::DetailFolderListView
    @Test("DetailFolderListView")
    func detailFolderListView() async throws {
        let root = WeatherRootModel.preview
        let model = root.itemController.itemOrEmpty(for: WeatherModel.previewId)

        try await assertDynamicSnapshot("DetailFolderListView") {
            DetailFolderListView(
                root: root,
                model: model,
                folderListController: root.folderListController,
                animate: .constant(false)
            )
        }
    }

    // snapshot-root: WeatherRPG::DetailListView
    @Test("DetailListView")
    func detailListView() async throws {
        let root = WeatherRootModel.preview
        let model = root.itemController.itemOrEmpty(for: WeatherModel.previewId)

        try await assertDynamicSnapshot("DetailListView") {
            DetailListView(
                root: root,
                model: model,
                folderListController: root.folderListController
            )
        }
    }

    // snapshot-root: WeatherRPG::OverlayViewer
    @Test("OverlayViewer")
    func overlayViewer() async throws {
        let root = WeatherRootModel.preview

        try await assertDynamicSnapshot("OverlayViewer") {
            OverlayViewer(
                model: root.itemController.itemOrEmpty(for: WeatherModel.previewId),
                animate: .constant(false)
            )
        }
    }

    // snapshot-root: WeatherRPG::WeatherConditionEditor
    @Test("WeatherConditionEditor")
    func weatherConditionEditor() async throws {
        let root = WeatherRootModel.preview
        let model = root.itemController.itemOrEmpty(for: WeatherModel.previewId)

        try await assertDynamicSnapshot("WeatherConditionEditor") {
            Form {
                WeatherConditionEditor(model: model)
            }
        }
    }

    // snapshot-root: WeatherRPG::WeatherEditor
    @Test("WeatherEditor")
    func weatherEditor() async throws {
        let root = WeatherRootModel.preview

        try await assertDynamicSnapshot("WeatherEditor") {
            WeatherEditor(
                model: root.itemController.itemOrEmpty(for: WeatherModel.previewId)
            )
        }
    }

    // snapshot-root: WeatherRPG::WeatherPhotoEditor
    @Test("WeatherPhotoEditor")
    func weatherPhotoEditor() async throws {
        let root = WeatherRootModel.preview
        let model = root.itemController.itemOrEmpty(for: WeatherModel.previewId)

        try await assertDynamicSnapshot("WeatherPhotoEditor") {
            Form {
                WeatherPhotoEditor(model: model)
            }
        }
    }

    // snapshot-root: WeatherRPG::WeatherStormEditor
    @Test("WeatherStormEditor")
    func weatherStormEditor() async throws {
        let root = WeatherRootModel.preview
        let model = root.itemController.itemOrEmpty(for: WeatherModel.previewId)

        try await assertDynamicSnapshot("WeatherStormEditor") {
            Form {
                WeatherStormEditor(model: model)
            }
        }
    }

    // snapshot-root: WeatherRPG::WeatherThunderEditor
    @Test("WeatherThunderEditor")
    func weatherThunderEditor() async throws {
        let root = WeatherRootModel.preview
        let model = root.itemController.itemOrEmpty(for: WeatherModel.previewId)

        try await assertDynamicSnapshot("WeatherThunderEditor") {
            Form {
                WeatherThunderEditor(model: model)
            }
        }
    }

    // snapshot-root: WeatherRPG::WeatherViewer
    @Test("WeatherViewer")
    func weatherViewer() async throws {
        try await assertDynamicSnapshot("WeatherViewer") {
            WeatherViewer(
                model: .heavy,
                size: CGSize(width: 375, height: 375),
                useGame: false,
                isAnimating: .constant(false)
            )
        }
    }

    private func assertDynamicSnapshot<Content: View>(
        _ name: String,
        @ViewBuilder content: () -> Content
    ) async throws {
        let container = try await WeatherRPGDynamicPreviewSnapshotFixtureCache.modelContainer()
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
private enum WeatherRPGDynamicPreviewSnapshotFixtureCache {
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
