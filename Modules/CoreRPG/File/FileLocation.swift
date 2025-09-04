// @copyright André Trettin

import Foundation

public enum FileLocation: Int, Equatable, Hashable, Codable, CaseIterable, Identifiable, Sendable {
    case oldAppCloud = 0
    case oldIcloud = 1
    case oldLocal = 2
    case oldOther = 3

    case cloud = 4
    case url = 5

    public var text: String {
        switch self {
        case .cloud: "Cloud"
        case .url: "Url"
        default: "Cloud"
        }
    }

    public var id: Int {
        rawValue
    }
}
