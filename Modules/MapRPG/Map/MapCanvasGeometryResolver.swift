// @copyright André Trettin

import CoreGraphics
import CoreRPG

// Split out of MapEditorModel.swift — has no dependency on MapEditorSession.
// See CODE_AUDIT §9.13.

/// Resolves legacy maps whose persisted canvas orientation no longer matches
/// their linked photo. Correct maps retain their persisted logical scale;
/// only a material aspect-ratio mismatch with image-compatible overlays uses
/// the photo's oriented dimensions.
struct MapCanvasGeometryResolver {
    @MainActor
    static func resolve(
        map: MapModel,
        mapSize: CGSize,
        imageSize: CGSize,
        degrees: Double
    ) -> CGSize {
        resolve(
            mapSize: mapSize,
            imageSize: imageSize,
            degrees: degrees,
            overlayBounds: overlayBounds(for: map)
        )
    }

    static func resolve(
        mapSize: CGSize,
        imageSize: CGSize,
        degrees: Double,
        overlayBounds: CGRect?
    ) -> CGSize {
        let orientedImageSize = ViewportGeometry.rotatedContentSize(
            imageSize,
            rotationDegrees: degrees
        )

        guard mapSize.isFiniteAndPositive else { return orientedImageSize }
        guard orientedImageSize.isFiniteAndPositive else { return mapSize }

        let mapAspectRatio = mapSize.width / mapSize.height
        let imageAspectRatio = orientedImageSize.width / orientedImageSize.height
        let aspectRatioError = abs(log(mapAspectRatio / imageAspectRatio))
        guard aspectRatioError > 0.03 else { return mapSize }

        guard let overlayBounds else { return orientedImageSize }
        let horizontalTolerance = max(44, orientedImageSize.width * 0.05)
        let verticalTolerance = max(44, orientedImageSize.height * 0.05)
        let supportedOverlayBounds = CGRect(origin: .zero, size: orientedImageSize)
            .insetBy(dx: -horizontalTolerance, dy: -verticalTolerance)

        return supportedOverlayBounds.contains(overlayBounds)
            ? orientedImageSize
            : mapSize
    }

    @MainActor
    private static func overlayBounds(for map: MapModel) -> CGRect? {
        var points = map.entries.flatMap(\.coordinates)
        points.append(contentsOf: map.mapPins.map(\.location))
        points.append(contentsOf: map.walls.flatMap { [$0.start, $0.end] })
        points.append(contentsOf: map.displayConfig.tileCoordinates)
        if map.pointer.location != .zero {
            points.append(map.pointer.location)
        }

        let finitePoints = points.filter { $0.x.isFinite && $0.y.isFinite }
        return finitePoints.bounds
    }
}
