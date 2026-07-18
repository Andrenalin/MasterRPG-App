// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct MapEditor: View {
    init(
        editController: EditController,
        image: AKImage,
        photoDegrees: Double,
        map: MapModel,
        configuration: MapEditorConfiguration,
        actions: MapEditorActions = MapEditorActions()
    ) {
        self.editController = editController
        self.image = image
        self.photoDegrees = photoDegrees
        self.map = map
        self.configuration = configuration
        mapEditController = MapEditController(editController: editController)
        _session = State(
            wrappedValue: MapEditorSession(
                map: map,
                image: image,
                photoDegrees: photoDegrees,
                configuration: configuration,
                actions: actions
            )
        )
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(MapRootModel.self) private var root
    @Environment(DropPinModel.self) private var dropPinModel
    @Environment(\.mapViewportTrailingInset) private var viewportTrailingInset

    private let editController: EditController
    private let image: AKImage
    private let photoDegrees: Double
    private let map: MapModel
    private let configuration: MapEditorConfiguration
    private let mapEditController: MapEditController

    @State private var session: MapEditorSession

    private var canvasConfiguration: MapCanvasConfiguration {
        MapCanvasConfiguration(
            mapId: map.id,
            imageIdentifier: ObjectIdentifier(image),
            imageSize: image.fixedSize,
            degrees: photoDegrees,
            mapSize: CGSize(width: map.width, height: map.height)
        )
    }

    var body: some View {
        ManagedNavigationStack(name: "MapEditor") { _ in
            MapEditorCanvas(
                session: session,
                image: image,
                degrees: photoDegrees,
                map: map
            )
            .padding(.trailing, max(0, viewportTrailingInset))
            .background {
                Rectangle()
                    .fill(Color.black.gradient)
                    .ignoresSafeArea()
            }
            .overlay {
                appearanceBackground.opacity(session.appeared ? 0 : 1)
            }
            .onChange(of: editController.editorModel.sheetEditorModel.itemId) {
                handleMapSelectionChange()
            }
            .onChange(
                of: editController.editorModel.sheetEditorModel.entryId,
                initial: true
            ) {
                handleEntrySelectionChange()
            }
            .onChange(of: map.mapPins) {
                handleExternalPinChange()
            }
            .onChange(of: map.entries) {
                handleExternalEntryChange()
            }
            .onChange(of: map.pointer) {
                session.resetPointer(map: map)
            }
            .onChange(of: canvasConfiguration, initial: true) {
                session.updateCanvas(
                    image: image,
                    photoDegrees: photoDegrees,
                    mapSize: canvasConfiguration.mapSize
                )
            }
            .onChange(of: dropPinModel.items) {
                dropPin()
            }
            .onChange(of: map.pinScale) {
                guard session.mapMode != .edit, map.pinScale != session.pinScale else { return }
                session.pinScale = map.pinScale
            }
            .onChange(of: session.pinScale) {
                guard session.mapMode != .edit else { return }
                map.pinScale = session.pinScale
            }
            .onChange(of: session.hexScale) {
                guard session.mapMode != .edit,
                      session.hexScale != 0,
                      session.hexScale != map.hexMapScale else { return }
                editController.createHexMap(model: map, hexMapScale: session.hexScale)
            }
            .onAppear(perform: appear)
            .onDisappear(perform: disappear)
            .modifier(
                EditToolBarViewModifier(
                    mapEditController: mapEditController,
                    editorModel: session,
                    isTileEditor: configuration.isTileEditor
                )
            )
        }
    }
}

private extension MapEditor {
    @ViewBuilder
    var appearanceBackground: some View {
        if colorScheme == .dark {
            Color.black.ignoresSafeArea()
        } else {
            Color.white.ignoresSafeArea()
        }
    }

    func appear() {
        installActionRouter()

        if session.mapMode != .edit,
           configuration.registersGameToolbarSession {
            if let previous = root.rootModel.gameEditorModel, previous !== session {
                session.isStreaming = previous.isStreaming
                session.isPointing = previous.isPointing
                if session.mapMode == .gameMaster {
                    session.displayMode = previous.displayMode
                }
            }
            root.rootModel.gameEditorModel = session
            session.resetReshare()
        }

        session.firstAppear(map: map)
        guard session.mapMode == .edit else { return }
        if configuration.isTileEditor {
            mapEditController.prepareTileWorkingCopy(from: map, editorModel: session)
        } else {
            mapEditController.prepareWorkingCopy(from: map, editorModel: session)
        }
    }

    func disappear() {
        if configuration.registersGameToolbarSession,
           root.rootModel.gameEditorModel === session {
            root.rootModel.gameEditorModel = nil
        }
        session.disappear()
        session.installActionRouter(nil)
    }

    func installActionRouter() {
        session.installActionRouter(
            MapEditorActionRouter(
                session: session,
                editController: editController,
                mapEditController: mapEditController,
                map: map,
                root: root
            )
        )
    }

    func handleMapSelectionChange() {
        session.changeImage(map: map)
        installActionRouter()

        if session.mapMode == .edit {
            if configuration.isTileEditor {
                mapEditController.prepareTileWorkingCopy(from: map, editorModel: session)
            } else {
                mapEditController.prepareWorkingCopy(from: map, editorModel: session)
                mapEditController.changeMap(
                    map: map,
                    currentEntryId: editController.editorModel.sheetEditorModel.entryId,
                    editorModel: session
                )
            }
        }
        session.firstAppear(map: map)
    }

    func handleEntrySelectionChange() {
        guard session.mapMode == .edit else { return }
        mapEditController.changeMap(
            map: map,
            currentEntryId: editController.editorModel.sheetEditorModel.entryId,
            editorModel: session
        )
    }

    func handleExternalPinChange() {
        mapEditController.mergeExternalPins(newMap: map, editorModel: session)
        let pins = session.mapMode == .edit
            ? session.workingCopy?.mapPins ?? map.mapPins
            : map.mapPins
        session.resetPlayerAndPins(newPins: pins, map: map, pinScale: session.pinScale)
    }

    func handleExternalEntryChange() {
        session.resetEntries(newEntries: map.entries, map: map)
        mapEditController.mergeExternalEntries(newMap: map, editorModel: session)
    }

    func dropPin() {
        guard !dropPinModel.items.isEmpty else { return }
        if session.mapMode == .edit {
            mapEditController.dropPin(
                at: dropPinModel.point,
                map: map,
                monsters: dropPinModel.items,
                editorModel: session
            )
        } else {
            let location = session.contentPoint(fromViewport: dropPinModel.point)
            let entry = session.entry(for: location, in: map)
            withAnimation(.bouncy) {
                root.editController.addMonsters(
                    map: map,
                    entryId: entry?.id,
                    location: location,
                    monsters: dropPinModel.items,
                    number: 1
                )
            }
        }
        dropPinModel.items = []
        dropPinModel.isTarget = false
    }
}

private struct MapCanvasConfiguration: Equatable {
    let mapId: UUID
    let imageIdentifier: ObjectIdentifier
    let imageSize: CGSize
    let degrees: Double
    let mapSize: CGSize
}

#Preview(traits: .mockData) {
    @Previewable @Environment(MapRootModel.self) var root

    Group {
#if os(macOS)
        MapEditor(
            editController: root.editController,
            image: AKImage(named: "photo") ?? AKImage(),
            photoDegrees: 0,
            map: MapModel.preview,
            configuration: MapEditorConfiguration(
                mode: .viewer,
                displayMode: .master
            )
        )
#else
        MapEditor(
            editController: root.editController,
            image: AKImage(systemName: "photo") ?? AKImage(),
            photoDegrees: 0,
            map: MapModel.preview,
            configuration: MapEditorConfiguration(
                mode: .viewer,
                displayMode: .master
            )
        )
#endif
    }
    .onAppear {
        root.editController.setCurrentItem(
            to: ItemRowTreeModel(
                itemId: root.itemController.itemDataModel.items[0],
                typeId: .map
            )
        )
    }
    .environment(DropPinModel())
}
