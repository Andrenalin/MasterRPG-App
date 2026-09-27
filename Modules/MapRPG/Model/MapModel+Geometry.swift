// @copyright André Trettin

import CoreGraphics
import CoreRPG
import Foundation

// Split out of MapModel.swift — see CODE_AUDIT §9.13.

public extension MapModel {
    /// Whether players see fog at this location: true when a hidden room
    /// polygon covers it. Locations outside every room are visible (no fog).
    func isLocationHiddenForPlayers(_ location: CGPoint) -> Bool {
        entries.contains { !$0.isShown && $0.contains(location) }
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

    func resetImage(with photoId: UUID, size: CGSize, degrees: Double) {
        let previousPhotoId = self.photoId
        self.photoId <=> photoId
        let oldCanvasSize = CGSize(width: width, height: height)
        let oldDegrees = self.degrees
        let newCanvasSize = ViewportGeometry.rotatedContentSize(size, rotationDegrees: degrees)
        guard newCanvasSize != oldCanvasSize || degrees != oldDegrees else { return }
        width = newCanvasSize.width
        height = newCanvasSize.height
        self.degrees = degrees
        resetEntryGeometry(
            oldCanvasSize: oldCanvasSize,
            oldDegrees: oldDegrees,
            previousPhotoIdMatches: previousPhotoId == photoId,
            newImageSize: size,
            newDegrees: degrees
        )
    }

    private func resetEntryGeometry(
        oldCanvasSize: CGSize,
        oldDegrees: Double,
        previousPhotoIdMatches: Bool,
        newImageSize: CGSize,
        newDegrees: Double
    ) {
        guard oldCanvasSize.width > 0,
              oldCanvasSize.height > 0,
              newImageSize.width > 0,
              newImageSize.height > 0 else { return }

        let transform: (CGPoint) -> CGPoint
        let oldImageSize = Self.imageSize(
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

        entries = entries.map {
            var replacedEntry = $0
            replacedEntry.coordinates = replacedEntry.coordinates.map(transform)
            return replacedEntry
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
            let source = entry.rect
            let others = entries.filter { !$0.isHexGrid && !$0.isShown }
            let stories = others.filter { $0.rect.intersects(source) }
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
        if displayState == DisplayStateMask.totalHidden.rawValue {
            entries.enumerated().forEach { index, _ in
                entries[index].isShown = false
            }
        }
    }
}
