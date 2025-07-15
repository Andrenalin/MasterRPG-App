// @copyright André Trettin

import Foundation

public protocol ItemDataAccessable {
    var displayState: Int32 { get }
}

public extension ItemDataAccessable {
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
