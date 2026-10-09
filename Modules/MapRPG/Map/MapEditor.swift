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
        trailingViewportReservation: CGFloat = 0,
        configuration: MapEditorConfiguration,
        actions: MapEditorActions = MapEditorActions()
    ) {
        self.editController = editController
        self.image = image
        self.photoDegrees = photoDegrees
        self.map = map
        self.trailingViewportReservation = trailingViewportReservation
        self.configuration = configuration
        mapEditController = MapEditController(editController: editController)
        // Built on first use, once. As a `State` initial value it was built on every init of
        // this view, with its viewport, pin model, room store over all entries and history,
        // and every instance but the first was thrown away: thousands of room nodes per
        // parent render on a hex map. See CODE_AUDIT_21 §7.9.
        _session = CoreRPG.LazyState(
            wrappedValue: MapEditorSession(
                map: map,
                image: image,
                photoDegrees: photoDegrees,
                configuration: configuration,
                actions: actions,
                trailingViewportReservation: trailingViewportReservation
            )
        )
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(MapRootModel.self) private var root
    @Environment(DropPinModel.self) private var dropPinModel

    private let editController: EditController
    private let image: AKImage
    private let photoDegrees: Double
    private let map: MapModel
    private let trailingViewportReservation: CGFloat
    private let configuration: MapEditorConfiguration
    private let mapEditController: MapEditController

    @CoreRPG.LazyState private var session: MapEditorSession

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
        Group {
            if configuration.mode == .edit {
                ManagedNavigationStack(name: "MapEditor") { _ in
                    MapEditorWindowStage(
                        session: session,
                        image: image,
                        degrees: photoDegrees,
                        map: map,
                        colorScheme: colorScheme
                    )
                    .modifier(
                        EditToolBarViewModifier(
                            mapEditController: mapEditController,
                            editorModel: session,
                            isTileEditor: configuration.isTileEditor
                        )
                    )
                    // The map renders beneath the editor bars, while their
                    // material remains an explicit non-map interaction layer.
                    // Toolbar taps therefore cannot fall through and append a
                    // room coordinate.
                    .modifier(MapEditorBottomBarBackdropModifier())
#if os(iOS)
                    .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                    .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                    // The title and subtitle toolbar items would otherwise open
                    // the large-title bar, which covers a tall strip of the map.
                    .navigationBarTitleDisplayMode(.inline)
#endif
                }
            } else {
                // A game surface belongs to GameScreenLayer's window viewport.
                // It must not introduce a nested navigation/safe-area owner.
                MapEditorWindowStage(
                    session: session,
                    image: image,
                    degrees: photoDegrees,
                    map: map,
                    colorScheme: colorScheme
                )
            }
        }
        .onChange(
            of: editController.editorModel.sheetEditorModel.entryId,
            initial: false
        ) { previousEntryId, currentEntryId in
            guard previousEntryId != currentEntryId else { return }
            handleEntrySelectionChange(currentEntryId: currentEntryId)
        }
        .onChange(of: map.mapPins) {
            handleExternalPinChange()
        }
        .onChange(of: map.entries) {
            handleExternalEntryChange()
        }
        .onChange(of: map.pointer) {
            guard session.mapId == map.id else { return }
            session.resetPointer(map: map)
        }
        .onChange(of: canvasConfiguration, initial: true) {
            synchronizeCanvas()
        }
        .onChange(of: dropPinModel.items) {
            dropPin()
        }
        .onChange(of: map.pinScale) {
            guard session.mapId == map.id,
                  session.mapMode != .edit,
                  map.pinScale != session.pinScale else { return }
            session.pinScale = map.pinScale
        }
        .onChange(of: trailingViewportReservation, initial: true) { _, reservation in
            session.updateTrailingViewportReservation(reservation)
        }
        .onChange(of: session.pinScale) {
            guard session.mapMode != .edit else { return }
            map.pinScale = session.pinScale
        }
        // On the release of the slider, not on `session.hexScale`: every value on the way
        // rebuilt the whole grid (up to 20,000 entries) on the main thread.
        // See CODE_AUDIT_21 §5.19.
        .onChange(of: session.hexScaleCommit) {
            guard session.mapMode != .edit,
                  session.isHexMap,
                  session.hexScale != 0,
                  session.hexScale != map.hexMapScale else { return }
            editController.createHexMap(model: map, hexMapScale: session.hexScale)
        }
        .focusedSceneValue(\.editorUndoActions, focusedUndoActions)
        .focusedSceneValue(
            \.selectedModule,
            configuration.mode == .edit
                ? Binding.constant(NetworkModules.map)
                : nil
        )
        .onAppear(perform: appear)
        .onDisappear(perform: disappear)
    }
}

private extension MapEditor {
    var focusedUndoActions: FocusedUndoActions? {
        guard configuration.mode == .edit else { return nil }

        return FocusedUndoActions(
            canUndo: session.history.canUndo,
            canRedo: session.history.canRedo,
            undoTitle: session.history.undoTitle,
            redoTitle: session.history.redoTitle,
            undo: {
                _ = mapEditController.undo(editorModel: session)
            },
            redo: {
                _ = mapEditController.redo(editorModel: session)
            }
        )
    }

    func synchronizeCanvas() {
        let mapChanged = session.mapId != map.id
        if mapChanged {
            session.changeImage(map: map)
            installActionRouter()
        }

        // Install the replacement map's actual logical/image geometry before
        // completing its first fit. This prevents a retained MapEditor view
        // from briefly fitting the previous map and treating that stale size
        // as its completed presentation.
        session.updateCanvas(
            map: map,
            image: image,
            photoDegrees: photoDegrees
        )

        if mapChanged {
            prepareEditorForCurrentMap()
            session.firstAppear(map: map)
        }
    }

    func appear() {
        installActionRouter()
        if session.mapMode != .edit {
            session.sharedRootModel = root.rootModel
        }

        if session.mapMode != .edit,
           configuration.registersGameToolbarSession {
            if let previous = root.rootModel.gameEditorModel, previous !== session {
                session.isPointing = previous.isPointing
                if session.mapMode == .gameMaster {
                    session.displayMode = previous.displayMode
                }
            }
            root.rootModel.gameEditorModel = session
            session.resetReshare()
        }

        prepareEditorForCurrentMap()
        session.firstAppear(map: map)
    }

    func disappear() {
        if configuration.registersGameToolbarSession,
           root.gameController.gameModel.currentItemId == nil,
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

    func prepareEditorForCurrentMap() {
        guard session.mapMode == .edit else { return }
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

    func handleEntrySelectionChange(currentEntryId: UUID?) {
        guard session.mapMode == .edit else { return }
        mapEditController.changeMap(
            map: map,
            currentEntryId: currentEntryId,
            editorModel: session
        )
    }

    func handleExternalPinChange() {
        guard session.mapId == map.id else { return }
        mapEditController.mergeExternalPins(newMap: map, editorModel: session)
        let pins = session.mapMode == .edit
            ? session.workingCopy?.mapPins ?? map.mapPins
            : map.mapPins
        session.resetPlayerAndPins(newPins: pins, map: map, pinScale: session.pinScale)
    }

    func handleExternalEntryChange() {
        guard session.mapId == map.id else { return }
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

/// A window-sized layout owner with the map viewport installed as a non-sizing
/// child. Editor chrome is applied to this stage, never to `MapEditorCanvas`.
private struct MapEditorWindowStage: View {
    let session: MapEditorSession
    let image: AKImage
    let degrees: Double
    let map: MapModel
    let colorScheme: ColorScheme

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Rectangle()
                    .fill(Color.black.gradient)
                    .ignoresSafeArea()
            }
            .overlay {
                MapEditorCanvas(
                    session: session,
                    image: image,
                    degrees: degrees,
                    map: map
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(
                    MapEditorCanvasSafeAreaModifier(
                        extendsUnderSystemBars: session.mapMode == .edit
                    )
                )
            }
            .overlay {
                if !session.appeared {
                    Group {
                        if colorScheme == .dark {
                            Color.black
                        } else {
                            Color.white
                        }
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
            }
    }
}

private struct MapEditorCanvasSafeAreaModifier: ViewModifier {
    let extendsUnderSystemBars: Bool

    func body(content: Content) -> some View {
#if os(iOS) || os(visionOS)
        if extendsUnderSystemBars {
            content.ignoresSafeArea(.container, edges: [.top, .bottom])
        } else {
            content
        }
#else
        content
#endif
    }
}

/// Blurs the map under the editor's bottom bar on iOS and visionOS, like the navigation bar's
/// material, to show that the map takes no taps there.
///
/// `toolbarBackground(_:for:)` draws nothing for `.bottomBar` since iOS 26, and visionOS has no
/// bar background at all, so the editor draws the strip itself.
private struct MapEditorBottomBarBackdropModifier: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS) || os(visionOS)
        content.overlay(alignment: .bottom) {
            // A zero-height view on the safe area's bottom edge. Its background extends over
            // the bottom safe area, which is exactly the strip the bar covers.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 0)
                .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
                .accessibilityHidden(true)
        }
#else
        content
#endif
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
