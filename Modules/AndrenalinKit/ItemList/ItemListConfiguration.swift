// @copyright André Trettin

import SwiftUI

public extension View {
    func itemListConfiguration(canAdd: Bool = true, modal: Bool = false, inline: Bool = true, modalOk: Bool = false, modalDismissAction: @escaping () -> Void = {}) -> some View {
        environment(\.itemListConfiguration, ItemListConfiguration(canAdd: canAdd, modal: modal, inline: inline, modalOk: modalOk, modalDismissAction: modalDismissAction))
    }

    func itemListChildrenConfiguration(canNavigate: Bool = true, disableSelection: Bool = false) -> some View {
        environment(\.itemListChildrenConfiguration, ItemListChildrenConfiguration(canNavigate: canNavigate, disableSelection: disableSelection))
    }
}

public extension EnvironmentValues {
    var itemListToggleAction: ItemListToggleAction {
        get { self[ItemListToggleActionKey.self] }
        set { self[ItemListToggleActionKey.self] = newValue }
    }
}

public struct ItemListToggleAction: Sendable {
    public init(toggler: @escaping @Sendable (UUID, NetworkModules) async -> Void) {
        self.toggler = toggler
    }

    public let toggler: @Sendable (UUID, NetworkModules) async -> Void

    public static let empty: ItemListToggleAction = ItemListToggleAction(toggler: { _, _ in })
}

// MARK: - Non public

struct ItemListToggleActionKey: EnvironmentKey {
    static let defaultValue: ItemListToggleAction = .empty
}

struct ItemListConfiguration {
    init(canAdd: Bool, modal: Bool, inline: Bool, modalOk: Bool, modalDismissAction: @escaping () -> Void) {
        self.canAdd = canAdd
        self.modal = modal
        self.inline = inline
        self.modalOk = modalOk
        self.modalDismissAction = modalDismissAction
    }

    var canAdd: Bool = true
    var modal: Bool = false
    var inline: Bool = true
    var modalOk: Bool = false
    var modalDismissAction: () -> Void
}

struct ItemListConfigurationKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = ItemListConfiguration(canAdd: true, modal: false, inline: true, modalOk: false, modalDismissAction: {})
}

extension EnvironmentValues {
    var itemListConfiguration: ItemListConfiguration {
        get { self[ItemListConfigurationKey.self] }
        set { self[ItemListConfigurationKey.self] = newValue }
    }
}

public struct ItemListChildrenConfiguration {
    public var canNavigate: Bool = true
    public var disableSelection: Bool = false
}

public extension EnvironmentValues {
    @Entry var itemListChildrenConfiguration = ItemListChildrenConfiguration()
}
