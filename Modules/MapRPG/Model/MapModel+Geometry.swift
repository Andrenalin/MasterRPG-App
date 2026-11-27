// @copyright André Trettin

import CoreGraphics
import CoreRPG
import Foundation
import os.log

// Split out of MapModel.swift — see CODE_AUDIT §9.13.

/// A photo's real pixel size and rotation — the geometry a map's rooms and pins were drawn on.
struct MapImageGeometry: Equatable, Sendable {
    let size: CGSize
    let degrees: Double

    var canvasSize: CGSize {
        ViewportGeometry.rotatedContentSize(size, rotationDegrees: degrees)
    }
}

public extension MapModel {
    /// Whether players see fog at this location: true when a hidden room
    /// polygon covers it. Locations outside every room are visible (no fog).
    func isLocationHiddenForPlayers(_ location: CGPoint) -> Bool {
        entries.contains { !$0.isShown && $0.contains(location) }
    }

    /// Whether a pin may be sent to players. The single source of the rule the client also
    /// applies when it renders: a pin must be shown, and a monster (a non-player pin) must not
    /// sit inside a hidden room. See CODE_AUDIT_23 §6.1.
    func isPinVisibleToPlayers(_ pin: MapPinModel) -> Bool {
        pin.isVisibleToPlayers(hiddenBy: entries)
    }

    /// Whether `pin` stands in `room`. A pin without a location is drawn in the map's first room
    /// (`MapPinPlacement.displayPins`), so it belongs there and nowhere else. See CODE_AUDIT_28 §5.6.
    func isPin(_ pin: MapPinModel, in room: MapEntryModel) -> Bool {
        if pin.location == .zero { return entries.first?.id == room.id }
        return room.contains(pin.location)
    }
}

public extension MapModel {
    /// The pins the players cannot see: hidden themselves or standing in a room that is not
    /// revealed. Read live from the map, so a reveal or a hide changes it at once.
    var hiddenPinIds: Set<UUID> {
        Set(mapPins.filter { !isPinVisibleToPlayers($0) }.map(\.id))
    }

    /// Whether the game master's full-screen photo of `pin` may go to the players. The
    /// presentation carries the pin's name and position, so the same rule as for the pin itself
    /// applies (shown, not in an unrevealed room), and nothing is shared while "Share Map" is
    /// paused. Otherwise the photo opens on the game master's device only.
    /// See CODE_AUDIT_24 §6.2.
    func mayShareFullScreenPhoto(of pin: MapPinModel, isStreaming: Bool) -> Bool {
        guard isStreaming else { return false }
        // The live pin decides: the copy a menu holds can be older than a reveal or a move.
        return isPinVisibleToPlayers(mapPins.first { $0.id == pin.id } ?? pin)
    }
}

public extension MapPinModel {
    /// `isShown` and, for a non-player pin, not covered by an unrevealed room in `entries`.
    func isVisibleToPlayers(hiddenBy entries: [MapEntryModel]) -> Bool {
        guard isShown else { return false }
        if isPlayer { return true }
        // A pin without a location is drawn in the map's first room, so that room decides.
        // See CODE_AUDIT_28 §5.6.
        if location == .zero, let first = entries.first { return first.isShown }
        return !entries.contains { !$0.isShown && $0.contains(location) }
    }
}

extension MapModel {
    subscript(_: MapPinId, positionId: MapPinModel.ID) -> MapPinModel {
        get {
            guard let index = mapPins.firstIndex(where: { $0.id == positionId }) else { return .empty(positionId) }
            return mapPins[index]
        }
        set {
            guard let index = mapPins.firstIndex(where: { $0.id == positionId }) else { return }
            mapPins[index] = newValue
        }
    }

    func setPinPointer(updatedPin: MapPinModel) {
        if pointer.id == updatedPin.id {
            pointer = updatedPin
        } else if let index = mapPins.firstIndex(where: { $0.id == updatedPin.id }) {
            mapPins[index] = updatedPin
        }
    }

    /// Whether the map has rooms, pins, walls or tiles whose coordinates depend on the canvas size.
    var hasCanvasContent: Bool {
        !entries.isEmpty || !mapPins.isEmpty || !walls.isEmpty || !displayConfig.tileCoordinates.isEmpty
    }

    /// Whether showing an image of `size` rotated by `degrees` gives the map another canvas size
    /// than `previous`, the real geometry of the current photo (the stored size when unknown).
    func changesCanvasSize(forImageSize size: CGSize, degrees: Double, comparedTo previous: MapImageGeometry? = nil) -> Bool {
        let oldCanvasSize = previous?.canvasSize ?? CGSize(width: width, height: height)
        return ViewportGeometry.rotatedContentSize(size, rotationDegrees: degrees) != oldCanvasSize
    }

    /// Whether showing an image of `size` rotated by `degrees` gives the canvas another shape than
    /// `previous` (the stored size when unknown), more than 1 % apart. "Adapt to New Size" then
    /// stretches rooms and pins, which the dialog says. See CODE_AUDIT_Since_3.0.1 §5.10.
    func changesAspectRatio(forImageSize size: CGSize, degrees: Double, comparedTo previous: MapImageGeometry? = nil) -> Bool {
        let oldCanvasSize = previous?.canvasSize ?? CGSize(width: width, height: height)
        let newCanvasSize = ViewportGeometry.rotatedContentSize(size, rotationDegrees: degrees)
        guard oldCanvasSize.width > 0, oldCanvasSize.height > 0, newCanvasSize.width > 0, newCanvasSize.height > 0 else { return false }
        let oldRatio = oldCanvasSize.width / oldCanvasSize.height
        let newRatio = newCanvasSize.width / newCanvasSize.height
        return abs(newRatio - oldRatio) / oldRatio > Self.aspectRatioTolerance
    }

    /// How far two canvas shapes may differ and still count as the same, for rounding in photo sizes.
    static let aspectRatioTolerance: Double = 0.01

    /// Records the rotation of a map saved before `degrees` was persisted. Its rooms, pins and walls
    /// already follow the photo's rotation, so the photo's degrees are adopted as the stored ones
    /// and no content moves; treating the unrecorded 0 as the old rotation would turn the content
    /// again on every repair. A map whose rotation is already recorded is left alone.
    func recordLegacyDegrees(_ photoDegrees: Double) {
        guard !hasRecordedDegrees else { return }
        degrees = photoDegrees
        hasRecordedDegrees = true
    }

    /// Installs the photo and the canvas size of its image. With `adaptContent` the rooms, pins,
    /// walls, pointer and tiles are scaled with it; without, they keep their absolute coordinates.
    /// `previousImage` is the real geometry of the photo being replaced. The stored width, height
    /// and degrees can be out of sync with it (e.g. on a duplicated map), so it wins when given.
    func resetImage(
        with photoId: UUID,
        size: CGSize,
        degrees: Double,
        adaptContent: Bool = true,
        previousImage: MapImageGeometry? = nil
    ) {
        // Whatever happens below, the rotation stored with the map now follows the photo.
        defer { hasRecordedDegrees = true }
        let previousPhotoId = self.photoId
        self.photoId <=> photoId
        let storedCanvasSize = CGSize(width: width, height: height)
        let oldCanvasSize = previousImage?.canvasSize ?? storedCanvasSize
        let oldDegrees = previousImage?.degrees ?? self.degrees
        let newCanvasSize = ViewportGeometry.rotatedContentSize(size, rotationDegrees: degrees)
        if let previousImage, previousImage.canvasSize != storedCanvasSize || previousImage.degrees != self.degrees {
            Logger.editController.warning("Map \(self.id, privacy: .public): stored canvas \(storedCanvasSize.debugDescription, privacy: .public) degrees \(self.degrees, privacy: .public) differs from the real old photo \(previousImage.size.debugDescription, privacy: .public) degrees \(previousImage.degrees, privacy: .public); using the photo.")
        }
        let canvasChanged = newCanvasSize != oldCanvasSize || degrees != oldDegrees
        guard canvasChanged || newCanvasSize != storedCanvasSize || degrees != self.degrees else { return }
        Logger.editController.debug("Map \(self.id, privacy: .public): replace photo old \(previousImage?.size.debugDescription ?? "stored", privacy: .public) -> new \(size.debugDescription, privacy: .public) degrees \(degrees, privacy: .public), canvas \(oldCanvasSize.debugDescription, privacy: .public) -> \(newCanvasSize.debugDescription, privacy: .public), adapt \(adaptContent, privacy: .public)")
        width = newCanvasSize.width
        height = newCanvasSize.height
        self.degrees = degrees
        guard adaptContent, canvasChanged else { return }
        resetEntryGeometry(
            oldCanvasSize: oldCanvasSize,
            oldDegrees: oldDegrees,
            previousPhotoIdMatches: previousPhotoId == photoId,
            oldImageSize: previousImage?.size,
            newImageSize: size,
            newDegrees: degrees
        )
    }

    private func resetEntryGeometry(
        oldCanvasSize: CGSize,
        oldDegrees: Double,
        previousPhotoIdMatches: Bool,
        oldImageSize knownOldImageSize: CGSize?,
        newImageSize: CGSize,
        newDegrees: Double
    ) {
        guard oldCanvasSize.width > 0,
              oldCanvasSize.height > 0,
              newImageSize.width > 0,
              newImageSize.height > 0 else { return }

        let transform: (CGPoint) -> CGPoint
        let oldImageSize = knownOldImageSize ?? Self.imageSize(
            fromCanvas: oldCanvasSize,
            degrees: oldDegrees
        ) ?? (previousPhotoIdMatches ? newImageSize : nil)
        if let oldImageSize {
            transform = { point in
                let oldImagePoint = ViewportGeometry.contentPoint(
                    fromRotated: point,
                    contentSize: oldImageSize,
                    rotationDegrees: oldDegrees
                )
                let resizedImagePoint = CGPoint(
                    x: oldImagePoint.x * newImageSize.width / oldImageSize.width,
                    y: oldImagePoint.y * newImageSize.height / oldImageSize.height
                )
                return ViewportGeometry.rotatedPoint(
                    fromContent: resizedImagePoint,
                    contentSize: newImageSize,
                    rotationDegrees: newDegrees
                )
            }
        } else {
            let horizontalScale = width / oldCanvasSize.width
            let verticalScale = height / oldCanvasSize.height
            transform = { point in
                CGPoint(
                    x: point.x * horizontalScale,
                    y: point.y * verticalScale
                )
            }
        }

        func moved(_ entry: MapEntryModel) -> MapEntryModel {
            var replacedEntry = entry
            replacedEntry.coordinates = replacedEntry.coordinates.map(transform)
            return replacedEntry
        }
        let oldHexCells = entries.filter(\.isHexGrid)
        entries = entries.filter { !$0.isHexGrid }.map(moved)
        if !oldHexCells.isEmpty {
            entries += rebuiltHexGrid(replacing: oldHexCells.map(moved), oldCanvasSize: oldCanvasSize)
        }
        mapPins = mapPins.map {
            var updatedPin = $0
            updatedPin.location = transform(updatedPin.location)
            return updatedPin
        }
        walls = walls.map {
            var updatedWall = $0
            updatedWall.start = transform(updatedWall.start)
            updatedWall.end = transform(updatedWall.end)
            return updatedWall
        }
        pointer.location = transform(pointer.location)
        var updatedDisplayConfig = displayConfig
        updatedDisplayConfig.tileCoordinates = updatedDisplayConfig.tileCoordinates.map(transform)
        displayConfig = updatedDisplayConfig
    }

    /// A new regular hex grid over the new canvas instead of the old cells transformed, which
    /// stretched every cell when the shape changed. The cell size follows the canvas, so about the
    /// same map area stays in one cell, and the revealed area carries over from `movedCells`, the
    /// old cells already moved to the new canvas. See CODE_AUDIT_Since_3.0.1 §5.10.
    private func rebuiltHexGrid(replacing movedCells: [MapEntryModel], oldCanvasSize: CGSize) -> [MapEntryModel] {
        let oldSize = hexMapScale > 0
            ? hexMapScale
            : (movedCells.map { cell in
                let xs = cell.coordinates.map(\.x)
                return (xs.max() ?? 0) - (xs.min() ?? 0)
            }.max() ?? 0) / sqrt(3)
        let factor = sqrt((width / oldCanvasSize.width) * (height / oldCanvasSize.height))
        guard oldSize > 0, factor.isFinite, factor > 0 else { return movedCells }
        let size = MapHexGridGeometry.fittedSize(oldSize * factor, width: width, height: height)
        let grid = MapHexGridGeometry.grid(for: size, in: CGRect(origin: .zero, size: CGSize(width: width, height: height)))
        guard !grid.isEmpty else { return movedCells }
        hexMapScale = size
        return MapHexGridGeometry.carryingRevealedArea(from: movedCells, to: grid)
    }

    private static func imageSize(
        fromCanvas canvasSize: CGSize,
        degrees: Double
    ) -> CGSize? {
        let normalizedDegrees = ViewportGeometry.normalize(rotationDegrees: degrees)
        switch normalizedDegrees {
        case 0, 180:
            return canvasSize
        case 90, 270:
            return CGSize(width: canvasSize.height, height: canvasSize.width)
        default:
            let radians = normalizedDegrees * .pi / 180
            let cosine = abs(cos(radians))
            let sine = abs(sin(radians))
            let determinant = cosine * cosine - sine * sine
            guard abs(determinant) > 0.000_001 else { return nil }

            let width = (cosine * canvasSize.width - sine * canvasSize.height) / determinant
            let height = (cosine * canvasSize.height - sine * canvasSize.width) / determinant
            guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
            return CGSize(width: width, height: height)
        }
    }

    func toggle(_ entryId: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else {
            return
        }
        let entry = entries[index]
        if entry.isHexGrid && !entry.isShown {
            // The room polygon must share an area with the cell, not only its bounding box: a hex
            // next to an L-shaped room revealed its name, text and pins. See CODE_AUDIT_29 §6.2.
            let others = entries.filter { !$0.isHexGrid && !$0.isShown }
            let stories = others.filter { $0.overlaps(entry) }
            stories.forEach { story in
                guard let storyIndex = entries.firstIndex(where: { $0.id == story.id }) else { return }
                entries[storyIndex].isShown = true
            }
        }
        entries[index].isShown.toggle()
    }

    func focused(_ entry: MapEntryModel) {
        entries.enumerated().forEach { index, sub in
            if entry.id == sub.id {
                entries[index].focused = !entries[index].focused
            } else {
                entries[index].focused = false
            }
        }
    }

    var children: [MapModel] {
        [self]
    }

    func resetEntries() {
        // Inline isHidden: the protocol convenience is @MainActor; this nonisolated
        // model reads its concrete stored property directly (called from didSet).
        if isHidden {
            entries.enumerated().forEach { index, _ in
                entries[index].isShown = false
            }
        }
    }
}
