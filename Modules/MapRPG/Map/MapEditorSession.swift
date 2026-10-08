// @copyright André Trettin

import CoreRPG
import SwiftUI

// Renamed from MapEditorModel.swift (the file's only type was MapEditorSession,
// not MapEditorModel) and split — see CODE_AUDIT §9.13:
// - MapEditorSession+Toolbar.swift: toolbar-scale reshare tracking
// - MapEditorSession+Content.swift: pins/entries sync, change/appear lifecycle
// - MapEditorSession+Viewport.swift: container size, zoom, viewport-fit
// - MapCanvasGeometryResolver.swift: standalone, no dependency on this type
//
// The `Dependencies` properties below are internal rather than `private` so
// the extensions above (in their own files) can reach them — Swift's
// `private` only extends to same-file extensions.

@MainActor @Observable
final class MapEditorSession {
    // MARK: - View State

    let configuration: MapEditorConfiguration
    let actions: MapEditorActions
    let viewport: ViewportModel
    var pins: MapPinViewModel
    let rooms: MapRoomStore
    let selection = MapEditorSelectionStore()
    var entries: MapEntryViewerModel { rooms.passive }
    var editEntries: MapEntryViewerModel { rooms.active }
    var focusId: MapEntryModel.ID?
    var appeared = false
    var mapId: UUID

    // Working copy of MapModel — owned here, mutated by MapEditController
    var workingCopy: MapModel?
    var undoDepthAtOpen: Int = 0
    let history: MapEditorHistory

    // MARK: - Toolbar State (merged from EditToolBarModel)

    var pinScale: CGFloat
    var hexScale: Double
    /// Counts the releases of the game toolbar's hex-scale slider; `MapEditor` rebuilds the grid
    /// when it changes. See CODE_AUDIT_21 §5.19.
    var hexScaleCommit = 0
    // Max room coordinate extent relative to the map image; 1.0 is the image boundary.
    var maxWidthRatio: Double = 1.0
    var maxHeightRatio: Double = 1.0
    // Set alongside maxWidthRatio/maxHeightRatio (which clamp at 1.0 and so can't
    // represent overflow by themselves) whenever a room coordinate actually falls
    // outside the map's stored width/height — see EditController.isMapSizeOutOfSync.
    var isMapSizeOutOfSync: Bool = false
    var lastPinScale: CGFloat = 1
    var lastHexScale: Double = 1
    var lastIsHexMap: Bool = false
    var isHexMap: Bool = false
    var displayMode: MapDisplayMode = .master
    var hideCloseButton: Bool = false

    // MARK: - Game Mode State

    var mapMode: MapMode { configuration.mode }
    var playerPinId: UUID? { configuration.playerPinId }
    /// The game toolbar's "Share Map" state, kept in the map root's `RootModel.isMapStreaming`
    /// once `MapEditor` attaches it, so the 2D map and the 3D table always agree.
    /// `localIsStreaming` only covers a session that has no root attached (yet).
    var isStreaming: Bool {
        get { sharedRootModel?.isMapStreaming ?? localIsStreaming }
        set {
            if let sharedRootModel {
                sharedRootModel.isMapStreaming = newValue
            } else {
                localIsStreaming = newValue
            }
        }
    }
    /// Weak: `RootModel.gameEditorModel` retains the game session.
    @ObservationIgnored weak var sharedRootModel: RootModel?
    private var localIsStreaming = true
    var isPointing: Bool = false
    var isPointerInteractionActive: Bool {
        mapMode == .gameMaster && isPointing
    }

    var roomHitTargetsAreEnabled: Bool {
        guard displayMode == .master, !isPointerInteractionActive else { return false }
        return switch mapMode {
        case .edit:
            editEntries.entries.isEmpty
        case .gameMaster:
            true
        case .player, .viewer:
            false
        }
    }

    var iconDisplayMode: String {
        switch displayMode {
        case .master: "rectangle.3.offgrid.fill"
        case .player: "rectangle.lefthalf.inset.filled"
        case .reader: "rectangle.3.offgrid"
        }
    }

    func toggleDisplayMode() {
        displayMode = switch displayMode {
        case .master: .player
        case .player: .reader
        case .reader: .master
        }
    }

    // MARK: - Dependencies

    var image: AKImage
    var photoDegrees: Double
    var canvasSize: CGSize
    var measuredContainerSize: CGSize
    var containerSize: CGSize
    var trailingViewportReservation: CGFloat = 0
    var pendingInitialFitMapId: UUID?
    var awaitingInitialRoomHydration = false
    var presentationIsActive = false
    @ObservationIgnored private var actionRouter: MapEditorActionRouter?

    // MARK: - Initialization

    init(
        map: MapModel,
        image: AKImage,
        photoDegrees: Double,
        containerSize: CGSize = .zero,
        configuration: MapEditorConfiguration,
        actions: MapEditorActions = MapEditorActions(),
        trailingViewportReservation: CGFloat = 0
    ) {
        self.configuration = configuration
        self.actions = actions
        self.image = image
        self.photoDegrees = photoDegrees
        let resolvedCanvasSize = Self.canvasSize(map: map, image: image, degrees: photoDegrees)
        let normalizedTrailingReservation = trailingViewportReservation.isFinite
            ? max(0, trailingViewportReservation)
            : 0
        let effectiveContainerSize = Self.effectiveContainerSize(
            measuredSize: containerSize,
            trailingReservation: normalizedTrailingReservation
        )
        self.canvasSize = resolvedCanvasSize
        self.measuredContainerSize = containerSize
        self.containerSize = effectiveContainerSize
        self.trailingViewportReservation = normalizedTrailingReservation
        self.pinScale = map.pinScale
        self.hexScale = map.hexMapScale
        self.lastPinScale = map.pinScale
        self.lastHexScale = map.hexMapScale
        self.isHexMap = map.entries.contains(where: { $0.isHexGrid })
        self.lastIsHexMap = map.entries.contains(where: { $0.isHexGrid })
        self.displayMode = configuration.displayMode
        self.mapId = map.id
        self.history = MapEditorHistory(map: map)
        self.pendingInitialFitMapId = effectiveContainerSize.isFiniteAndPositive
            && resolvedCanvasSize.isFiniteAndPositive
            ? nil
            : map.id

        let viewportConfiguration = ViewportConfiguration(
            id: map.id,
            contentSize: resolvedCanvasSize,
            containerSize: effectiveContainerSize,
            maximumScaleMultiplier: 8,
            panPolicy: .minimumVisible(44)
        )
        let viewportModel = ViewportModel(configuration: viewportConfiguration)
        self.viewport = viewportModel
        self.pins = MapPinViewModel(mapPins: map.mapPins, pointer: map.pointer)
        // Game mode seeds entries immediately (no working-copy merge needed); edit mode
        // starts empty and lets firstAppear/resetEntries do the merge against the working copy.
        self.rooms = MapRoomStore(
            mapId: map.id,
            passiveEntries: configuration.mode == .edit ? [] : map.entries
        )

        pins.configureInteractionHandler { [weak self] event in
            self?.handlePinSelection(event)
        }
        rooms.active.configureNeedleSelectionHandler { [weak self] point in
            self?.handleNeedleSelection(point)
        }
    }

    convenience init(
        map: MapModel,
        image: AKImage,
        photoDegrees: Double,
        containerSize: CGSize,
        displayMode: MapDisplayMode = .master,
        mapMode: MapMode = .edit,
        playerPinId: UUID? = nil
    ) {
        self.init(
            map: map,
            image: image,
            photoDegrees: photoDegrees,
            containerSize: containerSize,
            configuration: MapEditorConfiguration(
                mode: mapMode,
                displayMode: displayMode,
                playerPinId: playerPinId
            )
        )
    }

    private func handlePinSelection(_ event: MapPinInteractionEvent) {
        switch event {
        case let .tap(pin, _):
            rooms.active.selectNeedle(nil)
            selection.selectPin(pins.isExpandedId == pin.id ? pin.id : nil)
        case let .longPress(pin, _):
            rooms.active.selectNeedle(nil)
            selection.selectPin(pins.isExpandedId == pin.id ? pin.id : nil)
        case .doubleTap:
            rooms.active.selectNeedle(nil)
            selection.selectPin(nil)
        case .beginMove:
            rooms.active.selectNeedle(nil)
            selection.selectPin(nil)
        case .action(.copy, _, _, _):
            // The duplicate took over the expanded action menu.
            selection.selectPin(pins.isExpandedId)
        case .move, .action:
            break
        }
        actionRouter?.handle(.pin(event))
    }

    private func handleNeedleSelection(_ point: MapNeedlePointModel?) {
        selection.selectNeedle(point?.id)
        if point != nil {
            pins.isExpandedId = nil
        }
    }

    func beginNeedleDrag(_ point: MapNeedlePointModel) {
        pins.isExpandedId = nil
        editEntries.selectNeedle(point)
        selection.selectNeedle(point.id)
    }

    func installActionRouter(_ router: MapEditorActionRouter?) {
        actionRouter = router
    }

    func route(_ event: MapEditorEvent) {
        actionRouter?.handle(event)
    }

    func clearSelections() {
        selection.clear()
        pins.isExpandedId = nil
        editEntries.selectNeedle(nil)
    }
}
