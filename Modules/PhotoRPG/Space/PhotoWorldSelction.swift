// @copyright André Trettin

#if os(visionOS)
import Foundation

public struct PhotoWorldSelection: Codable, Hashable, Identifiable {
    public init(id: UUID, rotationDegrees: Double) {
        self.id = id
        self.rotationDegrees = rotationDegrees
    }
    
    public let id: UUID
    public let rotationDegrees: Double

    @MainActor
    public static let empty = PhotoWorldSelection(id: UUID(), rotationDegrees: 0.0)
}

#endif
