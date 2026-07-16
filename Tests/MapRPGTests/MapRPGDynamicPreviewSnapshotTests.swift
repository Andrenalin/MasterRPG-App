// @copyright André Trettin

import AudioRPG
import CharacterRPG
import CoreRPG
import DiceRPG
import GeneratorRPG
import PdfRPG
import PhotoRPG
import SnapshotTesting
import SwiftData
import SwiftUI
import TableRPG
import Testing
@testable import MapRPG

@MainActor
@Suite(.serialized, .snapshots, .tags(.snapshot))
struct MapRPGDynamicPreviewSnapshotTests {
    // snapshot-root: MapRPG::DisplayMapViewer
    @Test("DisplayMapViewer")
    func displayMapViewer() async throws {
        try await assertDynamicSnapshot("DisplayMapViewer") {
            DisplayMapViewer(
                image: AKImage(),
                itemId: MapModel.previewId,
                entryId: .constant(MapEntryModel.previewId),
                size: CGSize(width: 320, height: 240)
            )
        }
    }

    // snapshot-root: MapRPG::GameToolBar
    @Test("GameToolBar")
    func gameToolBar() async throws {
        let editorModel = MapEditorModel(
            map: .empty,
            image: AKImage(),
            photoDegrees: 0,
            containerSize: CGSize(width: 400, height: 600),
            mapMode: .gameMaster
        )

        try await assertDynamicSnapshot("GameToolBar") {
            GameToolBar(editController: .preview, model: editorModel, isMaster: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // snapshot-root: MapRPG::HexMapScaleView
    @Test("HexMapScaleView")
    func hexMapScaleView() async throws {
        let model = makeEditorModel()

        try await assertDynamicSnapshot("HexMapScaleView") {
            HexMapScaleView(model: model, onScaleChanged: { _ in })
                .padding()
                .background(.black)
        }
    }

    // snapshot-root: MapRPG::MapEditor
    @Test("MapEditor")
    func mapEditor() async throws {
        let root = MapRootModel.preview
        root.editController.setCurrentItem(
            to: ItemRowTreeModel(itemId: MapModel.previewId, typeId: .map)
        )

        try await assertDynamicSnapshot("MapEditor") {
            MapEditor(
                editController: root.editController,
                image: AKImage(),
                photoDegrees: 0,
                map: .preview,
                viewMode: .master,
                containerSize: CGSize(width: 390, height: 720),
                mapMode: .viewer
            )
            .environment(DropPinModel())
        }
    }

    // snapshot-root: MapRPG::MapPinView
    @Test("MapPinView")
    func mapPinView() async throws {
        let pin = MapPinModel.empty(MapRPGDynamicPreviewFixtures.pinID)
        let model = MapPinViewModel(mapPins: [pin], pointer: .empty(MapRPGDynamicPreviewFixtures.pointerID))

        try await assertDynamicSnapshot("MapPinView") {
            MapPinView(
                model: model,
                pinId: pin.id,
                pinSize: CGSize(width: 64, height: 64),
                isShown: true,
                borderColor: .yellow,
                canDrag: true,
                doubleTapAction: {},
                dragEndAction: {}
            )
            .padding()
        }
    }

    // snapshot-root: MapRPG::MaxSizeScaleView
    @Test("MaxSizeScaleView")
    func maxSizeScaleView() async throws {
        let model = makeEditorModel()

        try await assertDynamicSnapshot("MaxSizeScaleView") {
            MaxSizeScaleView(
                model: model,
                onMaxWidthChanged: { _ in },
                onMaxHeightChanged: { _ in }
            )
            .padding()
            .background(.black)
        }
    }

    // snapshot-root: MapRPG::NeedleMapPin
    @Test("NeedleMapPin")
    func needleMapPin() async throws {
        let root = MapRootModel.preview
        let entries = MapEntryViewerModel(
            mapId: MapModel.previewId,
            entries: [.previewGreatHall]
        )

        try await assertDynamicSnapshot("NeedleMapPin") {
            ZStack(alignment: .topLeading) {
                Color.yellow
                NeedleMapPin(
                    entries: entries,
                    entryId: MapEntryModel.previewGreatHall.id,
                    index: 0,
                    map: .preview,
                    mapEditController: MapEditController(editController: root.editController)
                )
                .padding(80)
            }
        }
    }

    // snapshot-root: MapRPG::PinScaleView
    @Test("PinScaleView")
    func pinScaleView() async throws {
        let model = makeEditorModel()

        try await assertDynamicSnapshot("PinScaleView") {
            PinScaleView(model: model)
                .padding()
                .background(.black)
        }
    }

    // snapshot-root: MapRPG::DetailRootView
    @Test("DetailRootView")
    func detailRootView() async throws {
        let root = MapRootModel.preview
        let model = root.itemController.itemOrEmpty(for: MapModel.previewId)

        try await assertDynamicSnapshot("DetailRootView") {
            ManagedNavigationStack {
                DetailRootView(root: root, model: model)
                    .preferredColorScheme(.dark)
            }
        }
    }

    // snapshot-root: MapRPG::ViewerRootView
    @Test("ViewerRootView")
    func viewerRootView() async throws {
        let root = MapRootModel.preview
        let model = root.itemController.itemOrEmpty(for: MapModel.previewId)

        try await assertDynamicSnapshot("ViewerRootView") {
            ManagedNavigationStack {
                ViewerRootView(model: model, configuration: ViewerConfiguration())
                    .preferredColorScheme(.dark)
            }
        }
    }

    // snapshot-root: MapRPG::DetailFolderListView
    @Test("DetailFolderListView")
    func detailFolderListView() async throws {
        let root = MapRootModel.preview
        let model = root.itemController.itemOrEmpty(for: MapModel.previewId)

        try await assertDynamicSnapshot("DetailFolderListView") {
            DetailFolderListView(
                root: root,
                model: model,
                folderListController: root.folderListController
            )
        }
    }

    // snapshot-root: MapRPG::DetailListView
    @Test("DetailListView")
    func detailListView() async throws {
        let root = MapRootModel.preview
        let model = root.itemController.itemOrEmpty(for: MapModel.previewId)

        try await assertDynamicSnapshot("DetailListView") {
            DetailListView(
                root: root,
                model: model,
                folderListController: root.folderListController
            )
        }
    }

    // snapshot-root: MapRPG::MapEditWindow
    @Test("MapEditWindow")
    func mapEditWindow() async throws {
        let root = MapRootModel.preview
        root.editController.setCurrentItem(
            to: ItemRowTreeModel(itemId: MapModel.previewId, typeId: .map)
        )

        try await assertDynamicSnapshot("MapEditWindow") {
            MapEditWindow(isTileEditor: false)
                .environment(DropPinModel())
        }
    }

    // snapshot-root: MapRPG::MapPinActionButtons
    @Test("MapPinActionButtons")
    func mapPinActionButtons() async throws {
        let pinID = MapRPGDynamicPreviewFixtures.pinID
        let model = MapPinViewModel(
            mapPins: [.empty(pinID)],
            pointer: .empty(MapRPGDynamicPreviewFixtures.pointerID)
        )
        model.isExpandedId = pinID

        try await assertDynamicSnapshot("MapPinActionButtons") {
            MapRPGDoubleNamespaceSnapshotHarness { glassNamespace, photoSpace in
                MapPinActionButtons(
                    model: model,
                    pinId: pinID,
                    layoutDown: true,
                    glassNamespace: glassNamespace,
                    photoSpace: photoSpace,
                    onRemove: {},
                    onCopy: {},
                    onResize: {},
                    onPhoto: {}
                )
                .frame(width: 300, height: 300)
                .background(.blue)
            }
        }
    }

    // snapshot-root: MapRPG::MapPinActionView
    @Test("MapPinActionView")
    func mapPinActionView() async throws {
        let pinID = MapRPGDynamicPreviewFixtures.pinID
        let model = MapPinViewModel(
            mapPins: [.empty(pinID)],
            pointer: .empty(MapRPGDynamicPreviewFixtures.pointerID)
        )
        model.isExpandedId = pinID

        try await assertDynamicSnapshot("MapPinActionView") {
            ZStack {
                Color.blue
                MapPinActionView(
                    model: model,
                    pinId: pinID,
                    layoutDown: true,
                    pinSize: CGSize(width: 80, height: 80),
                    isShown: true,
                    borderColor: .red,
                    canDrag: true,
                    showActions: true,
                    doubleTapAction: {},
                    dragEndAction: {}
                )
            }
        }
    }

    private func makeEditorModel() -> MapEditorModel {
        MapEditorModel(
            map: .previewEmpty,
            image: AKImage(),
            photoDegrees: 0,
            containerSize: CGSize(width: 320, height: 240)
        )
    }

    private func assertDynamicSnapshot<Content: View>(
        _ name: String,
        @ViewBuilder content: () -> Content
    ) async throws {
        let container = try await MapRPGDynamicPreviewSnapshotFixtureCache.modelContainer()
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
private struct MapRPGDoubleNamespaceSnapshotHarness<Content: View>: View {
    @Namespace private var firstNamespace
    @Namespace private var secondNamespace
    private let content: (Namespace.ID, Namespace.ID) -> Content

    init(@ViewBuilder content: @escaping (Namespace.ID, Namespace.ID) -> Content) {
        self.content = content
    }

    var body: some View {
        content(firstNamespace, secondNamespace)
    }
}

private enum MapRPGDynamicPreviewFixtures {
    static let pinID = UUID(uuid: (0xB1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    static let pointerID = UUID(uuid: (0xB1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
}

@MainActor
private enum MapRPGDynamicPreviewSnapshotFixtureCache {
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
