// @copyright André Trettin

import SwiftUI
#if os(macOS)
import AppKit
#elseif !os(tvOS)
import UIKit
#endif

#if !os(tvOS)
/// The Edit menu's pasteboard group (Cut, Copy, Paste, Delete, Select All), replaced so that
/// "Delete" deletes the selected item of the module and "Select All" is one entry: it selects the
/// rows of a module list in selection mode and the text of the focused field otherwise.
/// "Select None" sits below it.
///
/// SwiftUI has no placement for Select All alone, so the whole group is replaced and the other
/// entries send the standard edit actions down the responder chain, as the system items do.
/// Used once for the app (not per module), so the group is never left empty in windows that
/// show no module.
public struct PasteboardCommands: Commands {
    public init(roots: [any ItemRootControllable]) {
        self.roots = roots
    }

    let roots: [any ItemRootControllable]

    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?
    @FocusedValue(\.listSelectionActions) private var listSelectionActions: FocusedListSelectionActions?

    private var selectedRoot: (any ItemRootControllable)? {
        roots.first { $0.configurable.module == selectedModule }
    }

    public var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            StandardEditActionButton(action: .cut, title: LocalizedStringResource("Cut", bundle: .module), shortcut: KeyboardShortcut("x", modifiers: .command))
            // Its own key: "Copy" is the noun appended to duplicated names.
            StandardEditActionButton(
                action: .copy,
                title: LocalizedStringResource("Edit Menu Copy", defaultValue: "Copy", bundle: .module),
                shortcut: KeyboardShortcut("c", modifiers: .command)
            )
            StandardEditActionButton(action: .paste, title: LocalizedStringResource("Paste", bundle: .module), shortcut: KeyboardShortcut("v", modifiers: .command))
            StandardEditActionButton(
                action: .pasteAndMatchStyle,
                title: LocalizedStringResource("Paste and Match Style", bundle: .module),
                shortcut: KeyboardShortcut("v", modifiers: [.command, .option, .shift])
            )
            // The module's Delete (the selected or checked items) in place of the system's.
            if let selectedRoot {
                DeleteItemButton(root: selectedRoot)
            }
            ListSelectionMenuButtons(root: selectedRoot, focused: listSelectionActions)
        }
    }
}

/// A standard edit action sent to the first responder, like the system Edit menu items do.
enum StandardEditAction {
    case cut
    case copy
    case paste
    case pasteAndMatchStyle
    case selectAll

    @MainActor
    func send() {
        #if os(macOS)
        NSApp.sendAction(selector, to: nil, from: nil)
        #else
        UIApplication.shared.sendAction(selector, to: nil, from: nil, for: nil)
        #endif
    }

    private var selector: Selector {
        #if os(macOS)
        switch self {
        case .cut: #selector(NSText.cut(_:))
        case .copy: #selector(NSText.copy(_:))
        case .paste: #selector(NSText.paste(_:))
        case .pasteAndMatchStyle: #selector(NSTextView.pasteAsPlainText(_:))
        case .selectAll: #selector(NSResponder.selectAll(_:))
        }
        #else
        switch self {
        case .cut: #selector(UIResponderStandardEditActions.cut(_:))
        case .copy: #selector(UIResponderStandardEditActions.copy(_:))
        case .paste: #selector(UIResponderStandardEditActions.paste(_:))
        case .pasteAndMatchStyle: #selector(UIResponderStandardEditActions.pasteAndMatchStyle(_:))
        case .selectAll: #selector(UIResponderStandardEditActions.selectAll(_:))
        }
        #endif
    }
}

private struct StandardEditActionButton: View {
    let action: StandardEditAction
    let title: LocalizedStringResource
    var shortcut: KeyboardShortcut?

    var body: some View {
        Button {
            action.send()
        } label: {
            Text(title)
        }
        .keyboardShortcut(shortcut)
    }
}

/// Select All / Select None. They resolve the actions in their own body, so they read the root
/// list's selection mode and update with it.
private struct ListSelectionMenuButtons: View {
    let root: (any ItemRootControllable)?
    let focused: FocusedListSelectionActions?

    var body: some View {
        let actions = root.map { ListSelectionMenuPolicy.resolved(focused: focused, root: $0) } ?? focused
        MenuBarSelectAllButton(actions: actions)
        SelectNoneListButton(actions: actions)
    }
}
#endif
