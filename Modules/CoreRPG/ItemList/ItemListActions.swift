// @copyright André Trettin

import SwiftUI

public extension EnvironmentValues {
    var addNewTypeValue: Int? {
        get { self[AddNewTypeValueKey.self] }
        set { self[AddNewTypeValueKey.self] = newValue }
    }
}

struct AddNewTypeValueKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

