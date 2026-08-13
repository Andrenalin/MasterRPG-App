// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import RealityKit

/// Physical dimensions (in meters) of the game table, shared by every
/// platform variant (visionOS TabletopKit table, iOS/macOS camera-based
/// table). Purely numeric with no platform dependency, so it's declared once
/// here instead of duplicated per platform file — see CODE_AUDIT §9.1.
enum GameMetrics {
    static let tableEdge: Float = 0.7
    static let tableThickness: Float = 0.0146
    static let mapSurfaceClearance: Float = 0.0005
    static let playerAreaDistanceFromCenter: Float = 0.29
    static let smallHeight: Float = 0.001
    static let boardHeight: Float = 0.055
    static let playerAreaSize = SIMD2<Float>(0.4, 0.1)
    static let playerHandSize = SIMD2<Float>(0.2, 0.1)
}
#endif
