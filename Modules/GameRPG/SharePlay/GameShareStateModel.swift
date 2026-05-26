// @copyright André Trettin

#if os(visionOS)
import Foundation
@preconcurrency import GroupActivities

@MainActor @Observable
final class GameShareStateModel {
    enum PresentationMode: String, Sendable, CaseIterable {
        case window    // 2D windowed game — loose SharePlay seating
        case tabletop  // TabletopKit volumetric — role-assigned seats
        case immersive // Shared RealityKit immersive space
    }

    var mode: PresentationMode = .window
    var isSharePlayActive: Bool = false
    var groupImmersionActive: Bool = false
    var isMaster: Bool = false

    var spatialTemplatePreference: SystemCoordinator.SpatialTemplatePreference {
        switch mode {
        case .window:    return .sideBySide
        case .tabletop:  return .surround.contentExtent(100)
        case .immersive: return .none
        }
    }
}
#endif
