// @copyright André Trettin

import Foundation

public enum FileLocation: Int, Equatable, Hashable, Codable, CaseIterable, Identifiable, Sendable {
    case appCloud = 0
    case icloud = 1
    case local = 2
    case other = 3

    case newCloud = 4
    case url = 5

    public var text: String {
        switch self {
        case .appCloud: "AppCloud"
        case .icloud: "iCloud"
        case .local: "Local"
        case .other: "Other"
        case .newCloud: "Cloud"
        case .url: "Url"
        }
    }

    public var id: Int {
        rawValue
    }
}

public enum FileLocationSelector: Int, Equatable, Hashable, Codable, CaseIterable, Identifiable {
    case appCloud = 0
    case icloud = 1
    case local = 2
    case other = 3
    case none = 4

    public var text: String {
        switch self {
        case .none:
            return "None"
        default:
            return FileLocation(rawValue: id)?.text ?? "Error"
        }
    }

    public var id: Int {
        rawValue
    }
}
