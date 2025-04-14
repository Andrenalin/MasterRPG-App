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

public extension EnvironmentValues {
    var itemListSelectionAction: @Sendable (UUID?) -> Void {
        get { self[ItemListSelectionActionKey.self] }
        set { self[ItemListSelectionActionKey.self] = newValue }
    }
}

struct ItemListSelectionActionKey: EnvironmentKey {
    static let defaultValue: @Sendable (UUID?) -> Void = { _ in }
}

public extension EnvironmentValues {
    var listRowOverlayChildAction: ((UUID, UUID) -> Void)? {
        get { self[ListRowOverlayChildActionKey.self] }
        set { self[ListRowOverlayChildActionKey.self] = newValue }
    }
}

struct ListRowOverlayChildActionKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: ((UUID, UUID) -> Void)? = nil
}

extension EnvironmentValues {
    var toggleSelectionAction: () -> [ItemRowModel] {
        get { self[ToggleSelectionActionKey.self] }
        set { self[ToggleSelectionActionKey.self] = newValue }
    }
}

struct ToggleSelectionActionKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: () -> [ItemRowModel] = { [] }
}
