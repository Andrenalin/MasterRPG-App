// @copyright André Trettin

import Foundation

public struct UniversalVTTPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct UniversalVTTResolution: Codable, Equatable, Sendable {
    public let mapOrigin: UniversalVTTPoint
    public let mapSize: UniversalVTTPoint
    public let pixelsPerGrid: Double

    public init(mapOrigin: UniversalVTTPoint, mapSize: UniversalVTTPoint, pixelsPerGrid: Double) {
        self.mapOrigin = mapOrigin
        self.mapSize = mapSize
        self.pixelsPerGrid = pixelsPerGrid
    }
}

public struct UniversalVTTPortal: Codable, Equatable, Sendable {
    public let position: UniversalVTTPoint?
    public let bounds: [UniversalVTTPoint]
    public let rotation: Double?
    public let isClosed: Bool
    public let isFreestanding: Bool
    /// All source metadata except the potentially large base64 `image` field.
    public let rawData: FoundryJSONValue

    public init(
        position: UniversalVTTPoint?,
        bounds: [UniversalVTTPoint],
        rotation: Double?,
        isClosed: Bool,
        isFreestanding: Bool,
        rawData: FoundryJSONValue
    ) {
        self.position = position
        self.bounds = bounds
        self.rotation = rotation
        self.isClosed = isClosed
        self.isFreestanding = isFreestanding
        self.rawData = rawData
    }
}

public struct UniversalVTTLight: Codable, Equatable, Sendable {
    public let position: UniversalVTTPoint
    public let range: Double?
    public let intensity: Double?
    public let color: String?
    public let castsShadows: Bool?
    public let rawData: FoundryJSONValue

    public init(
        position: UniversalVTTPoint,
        range: Double?,
        intensity: Double?,
        color: String?,
        castsShadows: Bool?,
        rawData: FoundryJSONValue
    ) {
        self.position = position
        self.range = range
        self.intensity = intensity
        self.color = color
        self.castsShadows = castsShadows
        self.rawData = rawData
    }
}

/// Lossless Universal VTT transport used by the MapRPG importer.
public struct UniversalVTTDocument: Codable, Equatable, Sendable {
    public let formatVersion: Double?
    public let resolution: UniversalVTTResolution
    public let lineOfSight: [[UniversalVTTPoint]]
    public let objectsLineOfSight: [[UniversalVTTPoint]]
    public let portals: [UniversalVTTPortal]
    public let lights: [UniversalVTTLight]
    /// SHA-256 of the complete, bounded Universal VTT source payload.
    public let sourceSHA256: String?
    /// Descriptor for the embedded base64 map image. Image bytes remain lazy.
    public let imageResource: FoundryPackageResource
    public let rawData: FoundryJSONValue

    public init(
        formatVersion: Double?,
        resolution: UniversalVTTResolution,
        lineOfSight: [[UniversalVTTPoint]],
        objectsLineOfSight: [[UniversalVTTPoint]] = [],
        portals: [UniversalVTTPortal],
        lights: [UniversalVTTLight],
        imageResource: FoundryPackageResource,
        rawData: FoundryJSONValue,
        sourceSHA256: String? = nil
    ) {
        self.formatVersion = formatVersion
        self.resolution = resolution
        self.lineOfSight = lineOfSight
        self.objectsLineOfSight = objectsLineOfSight
        self.portals = portals
        self.lights = lights
        self.sourceSHA256 = sourceSHA256
        self.imageResource = imageResource
        self.rawData = rawData
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Double.self, forKey: .formatVersion)
        resolution = try container.decode(UniversalVTTResolution.self, forKey: .resolution)
        lineOfSight = try container.decode([[UniversalVTTPoint]].self, forKey: .lineOfSight)
        objectsLineOfSight = try container.decodeIfPresent(
            [[UniversalVTTPoint]].self,
            forKey: .objectsLineOfSight
        ) ?? []
        portals = try container.decode([UniversalVTTPortal].self, forKey: .portals)
        lights = try container.decode([UniversalVTTLight].self, forKey: .lights)
        sourceSHA256 = try container.decodeIfPresent(String.self, forKey: .sourceSHA256)
        imageResource = try container.decode(FoundryPackageResource.self, forKey: .imageResource)
        rawData = try container.decode(FoundryJSONValue.self, forKey: .rawData)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(formatVersion, forKey: .formatVersion)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(lineOfSight, forKey: .lineOfSight)
        try container.encode(objectsLineOfSight, forKey: .objectsLineOfSight)
        try container.encode(portals, forKey: .portals)
        try container.encode(lights, forKey: .lights)
        try container.encodeIfPresent(sourceSHA256, forKey: .sourceSHA256)
        try container.encode(imageResource, forKey: .imageResource)
        try container.encode(rawData, forKey: .rawData)
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case resolution
        case lineOfSight
        case objectsLineOfSight
        case portals
        case lights
        case sourceSHA256
        case imageResource
        case rawData
    }
}

public struct UniversalVTTReader: Sendable {
    public let limits: FoundryImportLimits

    public init(limits: FoundryImportLimits = .default) {
        self.limits = limits
    }

    public func read(from url: URL) async throws -> UniversalVTTDocument {
        let limits = limits
        // Structured and scope-balanced; cancellation propagates. See CODE_AUDIT_18 §4.4.
        return try await url.withSecurityScopedAccess { url in
            return try Self.readSynchronously(from: url, limits: limits)
        }
    }

    public func resourceData(
        for resource: FoundryPackageResource,
        from url: URL
    ) async throws -> FoundryPackageResourceData {
        let limits = limits
        // Structured and scope-balanced; cancellation propagates. See CODE_AUDIT_18 §4.4.
        return try await url.withSecurityScopedAccess { url in
            let data = try Self.imageDataSynchronously(from: url, limits: limits)
            guard resource == (try Self.resource(for: data)),
                  resource.byteCount == data.count,
                  resource.sha256 == foundrySHA256(data) else {
                throw FoundryImportError.resourceIntegrityFailure(resource.logicalPath)
            }
            return FoundryPackageResourceData(resource: resource, data: data)
        }
    }
}

extension UniversalVTTReader {
    static func readSynchronously(from url: URL, limits: FoundryImportLimits) throws -> UniversalVTTDocument {
        try Task.checkCancellation()
        let data = try boundedData(from: url, limits: limits)
        let raw = try decodeRaw(data)
        try Task.checkCancellation()
        guard let resolutionRaw = raw["resolution"], resolutionRaw.objectValue != nil else {
            throw FoundryImportError.invalidDocument(pack: "Universal VTT", key: "resolution")
        }
        let origin = try point(
            resolutionRaw["map_origin"],
            key: "resolution.map_origin",
            limits: limits
        )
        let size = try point(
            resolutionRaw["map_size"],
            key: "resolution.map_size",
            limits: limits
        )
        guard size.x > 0, size.y > 0,
              let pixelsPerGrid = resolutionRaw["pixels_per_grid"]?.universalNumber,
              isBoundedFinite(pixelsPerGrid, maximumMagnitude: limits.maximumUniversalVTTPixelDimension),
              pixelsPerGrid > 0,
              isValidPixelDimension(size.x * pixelsPerGrid, limits: limits),
              isValidPixelDimension(size.y * pixelsPerGrid, limits: limits) else {
            throw FoundryImportError.invalidDocument(pack: "Universal VTT", key: "resolution")
        }
        let formatVersion = try optionalBoundedNumber(
            raw["format"],
            key: "format",
            minimum: -limits.maximumUniversalVTTCoordinateMagnitude,
            maximum: limits.maximumUniversalVTTCoordinateMagnitude
        )
        var elementBudget = UniversalVTTElementBudget(maximum: limits.maximumUniversalVTTElementCount)
        let lineOfSight = try polygons(
            raw["line_of_sight"],
            key: "line_of_sight",
            limits: limits,
            budget: &elementBudget
        )
        let objectsLineOfSight = try polygons(
            raw["objects_line_of_sight"],
            key: "objects_line_of_sight",
            limits: limits,
            budget: &elementBudget
        )
        let portals = try portals(
            raw["portals"],
            limits: limits,
            budget: &elementBudget
        )
        let lights = try lights(
            raw["lights"],
            limits: limits,
            budget: &elementBudget
        )
        let imageData = try imageData(raw: raw, limits: limits)
        return UniversalVTTDocument(
            formatVersion: formatVersion,
            resolution: UniversalVTTResolution(mapOrigin: origin, mapSize: size, pixelsPerGrid: pixelsPerGrid),
            lineOfSight: lineOfSight,
            objectsLineOfSight: objectsLineOfSight,
            portals: portals,
            lights: lights,
            imageResource: try resource(for: imageData),
            rawData: raw.removingUniversalVTTImage,
            sourceSHA256: foundrySHA256(data)
        )
    }

    static func imageDataSynchronously(from url: URL, limits: FoundryImportLimits) throws -> Data {
        try Task.checkCancellation()
        let raw = try decodeRaw(boundedData(from: url, limits: limits))
        try Task.checkCancellation()
        return try imageData(raw: raw, limits: limits)
    }
}

private extension UniversalVTTReader {
    static func boundedData(from url: URL, limits: FoundryImportLimits) throws -> Data {
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true,
              let size = values.fileSize,
              size <= limits.maximumArchiveSize else {
            throw FoundryImportError.fileTooLarge(values.fileSize ?? Int.max)
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try Task.checkCancellation()
        return data
    }

    static func decodeRaw(_ data: Data) throws -> FoundryJSONValue {
        do {
            return try FoundryJSONDecoding.decodeSource(data)
        } catch {
            throw FoundryImportError.invalidArchive("The Universal VTT file is not valid JSON.")
        }
    }

    static func imageData(raw: FoundryJSONValue, limits: FoundryImportLimits) throws -> Data {
        guard let encodedValue = raw["image"]?.stringValue else {
            throw FoundryImportError.invalidDocument(pack: "Universal VTT", key: "image")
        }
        let encoded: String
        if encodedValue.prefix(5).lowercased() == "data:" {
            guard let comma = encodedValue.firstIndex(of: ","),
                  encodedValue.distance(from: encodedValue.startIndex, to: comma) <= 256,
                  encodedValue[..<comma].lowercased().hasSuffix(";base64") else {
                throw FoundryImportError.invalidDocument(pack: "Universal VTT", key: "image")
            }
            encoded = String(encodedValue[encodedValue.index(after: comma)...])
        } else {
            encoded = encodedValue
        }
        let data = try FoundryBoundedBase64.decode(
            encoded,
            maximumDecodedByteCount: limits.maximumEntrySize,
            invalidMessage: "The Universal VTT image is not valid base64."
        )
        guard imageFormat(for: data) != nil else {
            throw FoundryImportError.invalidDocument(pack: "Universal VTT", key: "image signature")
        }
        return data
    }

    static func point(
        _ value: FoundryJSONValue?,
        key: String,
        limits: FoundryImportLimits
    ) throws -> UniversalVTTPoint {
        guard let x = value?["x"]?.universalNumber,
              let y = value?["y"]?.universalNumber,
              isBoundedFinite(x, maximumMagnitude: limits.maximumUniversalVTTCoordinateMagnitude),
              isBoundedFinite(y, maximumMagnitude: limits.maximumUniversalVTTCoordinateMagnitude) else {
            throw FoundryImportError.invalidDocument(pack: "Universal VTT", key: key)
        }
        return UniversalVTTPoint(x: x, y: y)
    }

    static func polygons(
        _ value: FoundryJSONValue?,
        key: String,
        limits: FoundryImportLimits,
        budget: inout UniversalVTTElementBudget
    ) throws -> [[UniversalVTTPoint]] {
        guard let value else { return [] }
        guard let rawPolygons = value.arrayValue else {
            throw FoundryImportError.invalidDocument(pack: "Universal VTT", key: key)
        }
        try budget.consume(rawPolygons.count)
        var result: [[UniversalVTTPoint]] = []
        result.reserveCapacity(rawPolygons.count)
        for (polygonIndex, rawPolygon) in rawPolygons.enumerated() {
            try Task.checkCancellation()
            guard let rawPoints = rawPolygon.arrayValue else {
                throw FoundryImportError.invalidDocument(
                    pack: "Universal VTT",
                    key: "\(key)[\(polygonIndex)]"
                )
            }
            try budget.consume(rawPoints.count)
            var points: [UniversalVTTPoint] = []
            points.reserveCapacity(rawPoints.count)
            for (pointIndex, rawPoint) in rawPoints.enumerated() {
                points.append(try point(
                    rawPoint,
                    key: "\(key)[\(polygonIndex)][\(pointIndex)]",
                    limits: limits
                ))
            }
            result.append(points)
        }
        return result
    }

    static func portals(
        _ value: FoundryJSONValue?,
        limits: FoundryImportLimits,
        budget: inout UniversalVTTElementBudget
    ) throws -> [UniversalVTTPortal] {
        guard let value else { return [] }
        guard let rawPortals = value.arrayValue else {
            throw FoundryImportError.invalidDocument(pack: "Universal VTT", key: "portals")
        }
        try budget.consume(rawPortals.count)
        var result: [UniversalVTTPortal] = []
        result.reserveCapacity(rawPortals.count)
        for (index, portal) in rawPortals.enumerated() {
            try Task.checkCancellation()
            guard portal.objectValue != nil else {
                throw FoundryImportError.invalidDocument(pack: "Universal VTT", key: "portals[\(index)]")
            }
            let position = try optionalPoint(
                portal["position"],
                key: "portals[\(index)].position",
                limits: limits
            )
            let bounds: [UniversalVTTPoint]
            if let rawBoundsValue = portal["bounds"] {
                guard let rawBounds = rawBoundsValue.arrayValue else {
                    throw FoundryImportError.invalidDocument(
                        pack: "Universal VTT",
                        key: "portals[\(index)].bounds"
                    )
                }
                try budget.consume(rawBounds.count)
                bounds = try rawBounds.enumerated().map { pointIndex, rawPoint in
                    try point(
                        rawPoint,
                        key: "portals[\(index)].bounds[\(pointIndex)]",
                        limits: limits
                    )
                }
            } else {
                bounds = []
            }
            let rotation = try optionalBoundedNumber(
                portal["rotation"],
                key: "portals[\(index)].rotation",
                minimum: -limits.maximumUniversalVTTCoordinateMagnitude,
                maximum: limits.maximumUniversalVTTCoordinateMagnitude
            )
            result.append(UniversalVTTPortal(
                position: position,
                bounds: bounds,
                rotation: rotation,
                isClosed: portal["closed"]?.boolValue ?? false,
                isFreestanding: portal["freestanding"]?.boolValue ?? false,
                rawData: portal.removingUniversalVTTImage
            ))
        }
        return result
    }

    static func lights(
        _ value: FoundryJSONValue?,
        limits: FoundryImportLimits,
        budget: inout UniversalVTTElementBudget
    ) throws -> [UniversalVTTLight] {
        guard let value else { return [] }
        guard let rawLights = value.arrayValue else {
            throw FoundryImportError.invalidDocument(pack: "Universal VTT", key: "lights")
        }
        try budget.consume(rawLights.count)
        var result: [UniversalVTTLight] = []
        result.reserveCapacity(rawLights.count)
        for (index, light) in rawLights.enumerated() {
            try Task.checkCancellation()
            guard light.objectValue != nil else {
                throw FoundryImportError.invalidDocument(pack: "Universal VTT", key: "lights[\(index)]")
            }
            result.append(UniversalVTTLight(
                position: try point(
                    light["position"],
                    key: "lights[\(index)].position",
                    limits: limits
                ),
                range: try optionalBoundedNumber(
                    light["range"],
                    key: "lights[\(index)].range",
                    minimum: 0,
                    maximum: limits.maximumUniversalVTTCoordinateMagnitude
                ),
                intensity: try optionalBoundedNumber(
                    light["intensity"],
                    key: "lights[\(index)].intensity",
                    minimum: -limits.maximumUniversalVTTCoordinateMagnitude,
                    maximum: limits.maximumUniversalVTTCoordinateMagnitude
                ),
                color: light["color"]?.stringValue,
                castsShadows: light["shadows"]?.boolValue,
                rawData: light
            ))
        }
        return result
    }

    static func optionalPoint(
        _ value: FoundryJSONValue?,
        key: String,
        limits: FoundryImportLimits
    ) throws -> UniversalVTTPoint? {
        guard let value, value != .null else { return nil }
        return try point(value, key: key, limits: limits)
    }

    static func optionalBoundedNumber(
        _ value: FoundryJSONValue?,
        key: String,
        minimum: Double,
        maximum: Double
    ) throws -> Double? {
        guard let value, value != .null else { return nil }
        guard let number = value.universalNumber,
              number.isFinite,
              number >= minimum,
              number <= maximum else {
            throw FoundryImportError.invalidDocument(pack: "Universal VTT", key: key)
        }
        return number
    }

    static func isBoundedFinite(_ value: Double, maximumMagnitude: Double) -> Bool {
        value.isFinite && maximumMagnitude.isFinite && maximumMagnitude >= 0
            && abs(value) <= maximumMagnitude
    }

    static func isValidPixelDimension(_ value: Double, limits: FoundryImportLimits) -> Bool {
        value.isFinite && value > 0 && limits.maximumUniversalVTTPixelDimension.isFinite
            && value <= limits.maximumUniversalVTTPixelDimension
    }

    static func imageFormat(for data: Data) -> UniversalVTTImageFormat? {
        if data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) {
            return .png
        }
        if data.starts(with: [0xff, 0xd8, 0xff]) {
            return .jpeg
        }
        if data.count >= 12,
           data.prefix(4) == Data("RIFF".utf8),
           data.dropFirst(8).prefix(4) == Data("WEBP".utf8) {
            return .webP
        }
        return nil
    }

    static func resource(for data: Data) throws -> FoundryPackageResource {
        guard let imageFormat = imageFormat(for: data) else {
            throw FoundryImportError.invalidDocument(pack: "Universal VTT", key: "image signature")
        }
        return FoundryPackageResource(
            logicalPath: "map.\(imageFormat.fileExtension)",
            packagePath: "universal-vtt/image",
            location: .packaged,
            byteCount: data.count,
            sha256: foundrySHA256(data)
        )
    }
}

private enum UniversalVTTImageFormat {
    case png
    case jpeg
    case webP

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .webP: "webp"
        }
    }
}

private struct UniversalVTTElementBudget {
    private(set) var count = 0
    let maximum: Int

    mutating func consume(_ amount: Int) throws {
        let (nextCount, overflow) = count.addingReportingOverflow(amount)
        guard amount >= 0, !overflow, nextCount <= maximum else {
            throw FoundryImportError.tooManyUniversalVTTElements(overflow ? Int.max : nextCount)
        }
        count = nextCount
    }
}

private extension FoundryJSONValue {
    var universalNumber: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .unsignedInteger(let value): Double(value)
        case .number(let value): value
        default: nil
        }
    }

    var removingUniversalVTTImage: Self {
        guard case .object(var object) = self else { return self }
        object.removeValue(forKey: "image")
        return .object(object)
    }
}
