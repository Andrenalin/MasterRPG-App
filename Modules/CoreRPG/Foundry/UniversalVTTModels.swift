// @copyright André Trettin

import Foundation

// The Universal VTT document models, split out of UniversalVTTReader.swift. See CODE_AUDIT_29 §9.9.

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
