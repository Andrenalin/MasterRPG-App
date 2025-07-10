// @copyright André Trettin

import Foundation

public enum FileLocation: Int, Equatable, Hashable, Codable, CaseIterable, Identifiable, Sendable {
    case cloud = 4
    case url = 5

    public var text: String {
        switch self {
        case .cloud: "Cloud"
        case .url: "Url"
        }
    }

    public var id: Int {
        rawValue
    }
}
