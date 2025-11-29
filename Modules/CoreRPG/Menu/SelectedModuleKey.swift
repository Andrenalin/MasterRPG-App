// @copyright André Trettin

import SwiftUI

public struct SelectedModuleKey: FocusedValueKey {
    public typealias Value = Binding<NetworkModules>
}

public extension FocusedValues {
    var selectedModule: Binding<NetworkModules>? {
        get { self[SelectedModuleKey.self] }
        set { self[SelectedModuleKey.self] = newValue }
    }
}

public struct SelectedGameModuleKey: FocusedValueKey {
    public typealias Value = Binding<NetworkModules>
}

public extension FocusedValues {
    var selectedGameModule: Binding<NetworkModules>? {
        get { self[SelectedGameModuleKey.self] }
        set { self[SelectedGameModuleKey.self] = newValue }
    }
}
