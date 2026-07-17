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
        let editorModel = MapEditorSession(
            map: .empty,
            image: AKImage(),
            photoDegrees: 0,
            containerSize: CGSize(width: 400, height: 600),
            configuration: MapEditorConfiguration(
                mode: .gameMaster,
                displayMode: .master
            )
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
                configuration: MapEditorConfiguration(
                    mode: .viewer,
                    displayMode: .master
                )
            )
            .environment(DropPinModel())
        }
    }

    // snapshot-root: MapRPG::MapPinView
    @Test("MapPinView")
    func mapPinView() async throws {
        let pins = MapRPGDynamicPreviewFixtures.presentationPins
        let model = MapPinViewModel(mapPins: pins, pointer: .empty)

        try await assertDynamicSnapshot("MapPinView") {
            VStack(spacing: 24) {
                ForEach(model.mapPinNodes) { node in
                    HStack {
                        Text(verbatim: node.pin.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        MapPinView(
                            model: node,
                            pinSize: CGSize(width: 64, height: 64),
                            canMove: true,
                            actionContext: .editor,
                            doubleTapAccessibilityLabel: "Toggle Pin Zoom"
                        )
                    }
                }
            }
            .padding(40)
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
        let entries = MapEntryViewerModel(
            mapId: MapModel.previewId,
            entries: [.previewGreatHall]
        )
        let point = try #require(entries.renderedNeedlePoints(
            for: MapEntryModel.previewGreatHall.id
        ).first)
        entries.selectNeedle(point)

        try await assertDynamicSnapshot("NeedleMapPin") {
            ZStack(alignment: .topLeading) {
                Color.yellow
                NeedleMapPin(
                    entries: entries,
                    entryId: MapEntryModel.previewGreatHall.id,
                    point: point,
                    session: nil
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
        let model = MapPinViewModel(mapPins: [.empty(pinID)], pointer: .empty)

        try await assertDynamicSnapshot("MapPinActionButtons") {
            MapRPGDoubleNamespaceSnapshotHarness { glassNamespace, photoSpace in
                MapPinActionButtons(
                    model: model.mapPinNodes[0],
                    context: .editor,
                    placement: MapAdaptiveFanGeometry.placement(
                        anchor: CGPoint(x: 150, y: 150),
                        itemCount: MapPinActionContext.editor.actions.count,
                        viewport: CGRect(x: 0, y: 0, width: 300, height: 300)
                    ),
                    glassNamespace: glassNamespace,
                    photoSpace: photoSpace,
                    usesGlassEffects: false
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
                    model: model.mapPinNodes[0],
                    pinScale: 80 / 44,
                    canDrag: true,
                    actionContext: .editor,
                    doubleTapAccessibilityLabel: "Toggle Player Visibility",
                    usesGlassEffects: false
                )
            }
        }
    }

    @Test("MapPinGameMasterActionView")
    func mapPinGameMasterActionView() async throws {
        let pinID = MapRPGDynamicPreviewFixtures.pinID
        var pin = MapPinModel.empty(pinID)
        pin.isDead = true
        pin.isHighlighted = true
        let model = MapPinViewModel(
            mapPins: [pin],
            pointer: .empty(MapRPGDynamicPreviewFixtures.pointerID)
        )
        model.isExpandedId = pinID

        try await assertDynamicSnapshot("MapPinGameMasterActionView") {
            ZStack {
                Color.blue
                MapPinActionView(
                    model: model.mapPinNodes[0],
                    pinScale: 80 / 44,
                    canDrag: true,
                    actionContext: .gameMaster,
                    doubleTapAccessibilityLabel: "Toggle Pin Zoom",
                    usesGlassEffects: false
                )
            }
        }
    }

    private func makeEditorModel() -> MapEditorSession {
        MapEditorSession(
            map: .previewEmpty,
            image: AKImage(),
            photoDegrees: 0,
            containerSize: CGSize(width: 320, height: 240),
            configuration: MapEditorConfiguration(
                mode: .edit,
                displayMode: .master
            )
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

    static let presentationPins: [MapPinModel] = {
        var alive = MapPinModel.empty(UUID(uuid: (0xB1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3)))
        alive.name = "Alive"

        var dead = MapPinModel.empty(UUID(uuid: (0xB1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4)))
        dead.name = "Dead"
        dead.isDead = true

        var highlighted = MapPinModel.empty(UUID(uuid: (0xB1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5)))
        highlighted.name = "Highlighted"
        highlighted.isHighlighted = true

        var combined = MapPinModel.empty(UUID(uuid: (0xB1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6)))
        combined.name = "Dead + Highlighted"
        combined.isDead = true
        combined.isHighlighted = true

        return [alive, dead, highlighted, combined]
    }()
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
