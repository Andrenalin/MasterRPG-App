// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
/// Which list the Select All / Select None commands act on and whether they are enabled: only a
/// focused list in selection mode takes them.
enum ListSelectionMenuPolicy {
    /// Whether Select All / Select None act on a list: only a module list in selection mode
    /// (`listSelectionActions` is published by the list). Outside it the menu bar's Select All
    /// selects the text of a focused field, see `MenuBarSelectAllButton`.
    static func isEnabled(_ actions: FocusedListSelectionActions?) -> Bool {
        actions?.isSelectionMode == true
    }

    /// The actions the menu bar commands run. The list's own focused actions win when a list
    /// holds the keyboard focus (they know a folder's own list), but the commands must not depend
    /// on that focus: a click on a row or its checkmark does not always move SwiftUI's focus
    /// there, and then the commands were disabled in selection mode. So they fall back to the
    /// module's root list, like Space, Return and Delete do, and selection mode is read from
    /// the root list as well.
    @MainActor
    static func resolved(focused: FocusedListSelectionActions?, root: any ItemRootControllable) -> FocusedListSelectionActions {
        let rootActions = rootActions(for: root.folderListControllable)
        guard let focused else { return rootActions }
        return FocusedListSelectionActions(
            isSelectionMode: focused.isSelectionMode || rootActions.isSelectionMode,
            selectAllFolderName: focused.selectAllFolderName,
            selectAll: focused.selectAll,
            selectNone: focused.selectNone
        )
    }

    @MainActor
    static func rootActions(for controller: any FolderListControllable) -> FocusedListSelectionActions {
        FocusedListSelectionActions(
            isSelectionMode: controller.listDisplayModel.isSelectionMode,
            selectAllFolderName: {
                controller.selectAllFolderName(in: controller.listModel, anchorRowId: controller.listModel.keyboardRowId)
            },
            selectAll: {
                withAnimation {
                    controller.selectAll(in: controller.listModel, anchorRowId: controller.listModel.keyboardRowId)
                }
            },
            selectNone: {
                withAnimation { controller.selectNone(in: controller.listModel) }
            }
        )
    }

    /// The menu bar's Select All: the list's rows in selection mode, the system's Select All
    /// (`fallback`, the text of a focused field) otherwise.
    @MainActor
    static func performSelectAll(_ actions: FocusedListSelectionActions?, fallback: () -> Void) {
        if let actions, isEnabled(actions) {
            actions.selectAll()
        } else {
            fallback()
        }
    }

    static let selectAllKey: KeyEquivalent = "a"
    static let selectAllModifiers: EventModifiers = [.command]
    /// Command-Shift-A is "Add into folder" in the list's context menu.
    static let selectNoneKey: KeyEquivalent = "a"
    static let selectNoneModifiers: EventModifiers = [.command, .option]
}

/// "Select All", or "Select All in <folder>" when it selects the content of a folder.
struct SelectAllLabel: View {
    let folderName: String?

    var body: some View {
        Label {
            if let folderName, !folderName.isEmpty {
                Text("Select All in \(folderName)", bundle: .module)
            } else {
                Text("Select All", bundle: .module)
            }
        } icon: {
            Image(systemName: "checkmark.circle.fill")
        }
    }
}

struct SelectAllListButton: View {
    let actions: FocusedListSelectionActions?
    /// The toolbar menu shows the entry without the shortcut; the menu bar owns it.
    var showsShortcut = true

    var body: some View {
        Button {
            actions?.selectAll()
        } label: {
            SelectAllLabel(folderName: actions?.selectAllFolderName())
        }
        .applyIf(valueFor(iOS: false, macOS: showsShortcut, tvOS: false, visionOS: false)) {
            $0.keyboardShortcut(ListSelectionMenuPolicy.selectAllKey, modifiers: ListSelectionMenuPolicy.selectAllModifiers)
        }
        .disabled(!ListSelectionMenuPolicy.isEnabled(actions))
    }
}

struct SelectNoneListButton: View {
    let actions: FocusedListSelectionActions?
    var showsShortcut = true

    var body: some View {
        Button {
            actions?.selectNone()
        } label: {
            Label {
                Text("Select None", bundle: .module)
            } icon: {
                Image(systemName: "circle")
            }
        }
        .applyIf(showsShortcut) {
            $0.keyboardShortcut(ListSelectionMenuPolicy.selectNoneKey, modifiers: ListSelectionMenuPolicy.selectNoneModifiers)
        }
        .disabled(!ListSelectionMenuPolicy.isEnabled(actions))
    }
}

/// The menu bar's Select All, which replaces the system one: it selects the rows while a module
/// list is in selection mode and otherwise sends Select All to the first responder (the text of a
/// focused field), so it stays enabled and keeps Command-A on every platform.
struct MenuBarSelectAllButton: View {
    let actions: FocusedListSelectionActions?

    var body: some View {
        let selectsRows = ListSelectionMenuPolicy.isEnabled(actions)
        Button {
            ListSelectionMenuPolicy.performSelectAll(actions) {
                StandardEditAction.selectAll.send()
            }
        } label: {
            SelectAllLabel(folderName: selectsRows ? actions?.selectAllFolderName() : nil)
        }
        .keyboardShortcut(ListSelectionMenuPolicy.selectAllKey, modifiers: ListSelectionMenuPolicy.selectAllModifiers)
    }
}
#endif
