// @copyright André Trettin

import Combine
import Foundation
import SwiftUI

public enum DisplayStateMask: Int {
    case fullVisible = 0
    case groupHidden = 1
    case totalHidden = 2
    case nameHidden = 4
    case descriptionHidden = 8
    case otherHidden = 16

    public func set(on value: Int) -> Int {
        value | rawValue
    }

    public func reset(on value: Int) -> Int {
        value & ~rawValue
    }

    public func toggle(on value: Int) -> Int {
        if value & rawValue == rawValue {
            return reset(on: value)
        } else {
            return set(on: value)
        }
    }
}

public extension ItemDataAccessable {
    static var typeId: NetworkModules { .none }

    var isHidden: Bool {
        displayState == DisplayStateMask.totalHidden.rawValue
    }

    var isGroupHidden: Bool {
        (displayState & DisplayStateMask.groupHidden.rawValue) > 0
    }

    var hideName: Bool {
        (displayState & DisplayStateMask.nameHidden.rawValue) > 0
    }

    var hideDescription: Bool {
        (displayState & DisplayStateMask.descriptionHidden.rawValue) > 0
    }

    var hideOther: Bool {
        (displayState & DisplayStateMask.otherHidden.rawValue) > 0
    }
}

public protocol ItemDuplicatable {
    func duplicate() -> Self
}

public extension ItemDuplicatable {
    func duplicateName(from original: String) -> String {
        let copyKey: LocalizedStringResource = "Copy"
        let copyString = String(localized: copyKey).localizedString
        return "\(original) \(copyString)"
    }
}
