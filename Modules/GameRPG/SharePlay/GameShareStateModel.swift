// @copyright André Trettin

#if os(visionOS)
import Foundation

/// `mode` is observed directly through an `Observations` sequence (see
/// `RPGSharePlayController.observeShareStateMode()`) rather than through a separate Combine
/// publisher: `@Observable` already notifies on every property change.
@MainActor @Observable
final class GameShareStateModel {
    enum PresentationMode: String, Sendable, CaseIterable, Codable {
        case window    // 2D windowed game — loose SharePlay seating
        case tabletop  // TabletopKit volumetric — role-assigned seats
        case immersive // Shared RealityKit immersive space
    }

    var mode: PresentationMode = .window

    var isSharePlayActive: Bool = false
    var groupImmersionActive: Bool = false
    var isMaster: Bool = false
}
#endif
