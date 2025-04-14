// @copyright André Trettin

import Foundation

public struct ScreenSizeModel: Equatable, Sendable {
    public init(size: CGSize) {
        self.size = size
    }
    
    public let size: CGSize
    
    public static let empty: ScreenSizeModel = ScreenSizeModel(size: .zero)
}
