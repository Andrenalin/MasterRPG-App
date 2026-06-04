// @copyright André Trettin

#if os(visionOS)
import Foundation
import Combine

@MainActor @Observable
final class GameShareStateModel {
    enum PresentationMode: String, Sendable, CaseIterable, Codable {
        case window    // 2D windowed game — loose SharePlay seating
        case tabletop  // TabletopKit volumetric — role-assigned seats
        case immersive // Shared RealityKit immersive space
    }

    var mode: PresentationMode = .window {
        didSet {
            if oldValue != mode {
                modeChangedSubject.send(mode)
            }
        }
    }
    
    var isSharePlayActive: Bool = false
    var groupImmersionActive: Bool = false
    var isMaster: Bool = false

    // ✅ Add publisher for mode changes so SharePlay can synchronize
    private let modeChangedSubject = PassthroughSubject<PresentationMode, Never>()
    var modeChanged: AnyPublisher<PresentationMode, Never> {
        modeChangedSubject.eraseToAnyPublisher()
    }
}
#endif
