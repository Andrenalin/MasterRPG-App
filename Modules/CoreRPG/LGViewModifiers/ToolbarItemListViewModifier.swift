// @copyright André Trettin

import SwiftUI
import TipKit

extension View {
    /// - Parameter showsDismissButton: Whether a `modal` list gets the checkmark button that
    ///   closes it. Pass `false` for a list in its own window, which the window controls close.
    public func toolbarItemListModifier(root: any ItemRootControllable, listControllable: any FolderListControllable, parentModel: (any ItemDataAccessible)?, modal: Bool = false, showsDismissButton: Bool = true, dismissHandler: (() -> Void)? = nil) -> some View {
        modifier(ToolbarItemListViewModifier(root: root, listController: listControllable, parentModel: parentModel, modal: modal, showsDismissButton: showsDismissButton, dismissHandler: dismissHandler))
    }
}

struct ToolbarItemListViewModifier: ViewModifier {
    let root: any ItemRootControllable
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessible)?
    let modal: Bool
    let showsDismissButton: Bool
    let dismissHandler: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .toolbar {
#if os(macOS)
                ToolbarItem(placement: .secondaryAction) {
                    ToolbarItemListActionMenuView(root: root, listController: listController, parentModel: parentModel, modal: modal)
                }
#else
                ToolbarItemGroup(placement: .secondaryActionAll) {
                    ToolbarItemListSecondaryActionMenuView(root: root, listController: listController, parentModel: parentModel, modal: modal)
#if os(visionOS)
                        .foregroundStyle(.primary)
#endif
                }
#endif
                // Single stable ToolbarItem — avoids _ConditionalContent in the preference tree
                // which would cause a deep AG graph traversal on every navigation transition.
                ToolbarItem(placement: .primaryAction) {
                    if listDisplayModel.isSelectionMode && modal == false {
                        MenuSelectionButtonView(listDisplayModel: listDisplayModel)
#if os(visionOS)
                            .foregroundStyle(.primary)
#endif
                    } else if modal == false || (parentModel != nil && parentModel!.specialCategory) {
                        addItemButton(for: .item, root: root, listController: listController, parentModel: parentModel)
#if os(visionOS)
                            .foregroundStyle(.primary)
#endif
                    }
                }

#if !os(macOS)
                ToolbarItem(placement: .confirmationAction) {
                    if modal == true && showsDismissButton {
                        ToolbarItemListDismissButtonView(dismissHandler: dismissHandler)
#if os(visionOS)
                            .foregroundStyle(.primary)
#endif
                    }
                }
#endif
            }
    }
}

private extension ToolbarItemListViewModifier {
    var listDisplayModel: ListDisplayModel {
        listController.listDisplayModel
    }
}

// These free functions were extracted from `ToolbarItemListViewModifier` and are called
// only from `View.body` contexts (which are `@MainActor` per SwiftUI's `View`/`ViewModifier`
// protocol conformance) — `@MainActor` restores the isolation they implicitly had as
// instance methods before extraction, since a plain top-level function gets none of that
// inference on its own. See CODE_AUDIT §8.3.
@MainActor
@ViewBuilder
private func toggleFolder(listController: any FolderListControllable) -> some View {
    Button {
        if let selected = listController.listModel.selected,
           let item = listController.listModel.list.first(where: { $0.source.itemId == selected }) {
            listController.toggleFolder(item: item)
        }
    } label: {
        Label {
            Text("Toggle Folder", bundle: .module)
        } icon: {
            Image(systemName: "list.bullet.indent")
        }
    }
}

@MainActor
@ViewBuilder
private func addItemButton(for type: EditControllerAddType, showTip: Bool = true, root: any ItemRootControllable, listController: any FolderListControllable, parentModel: (any ItemDataAccessible)? = nil) -> some View {
    let button = Button {
        Task {
            await addItem(for: type, listController: listController, root: root, parentId: parentModel?.id)
        }
    } label: {
        Label {
            Text(type.title)
        } icon: {
            Image(systemName: type.icon(collection: root.itemControllable.collectionCategory.icon))
        }
    }
    if type == .item && showTip {
        button
            .popoverTip(MasterRPGTips.firstItem)
    } else {
        button
    }
}

@MainActor
private func addItem(for type: EditControllerAddType, listController: any FolderListControllable, root: any ItemRootControllable, parentId: UUID?) async {
    listController.add(type: type, url: nil, root: root, parentId: parentId)
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct ToolbarItemListActionMenuView: View {
    let root: any ItemRootControllable
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessible)?
    let modal: Bool

    private var listModel: FolderListModel {
        listController.listModel
    }

    private var listDisplayModel: ListDisplayModel {
        listController.listDisplayModel
    }

    @ViewBuilder
    var body: some View {
        Menu {
            MenuDisplayModeToggle(listDisplayModel: listDisplayModel, showSelectionButton: false, modal: modal) {
                if parentModel == nil && modal == false {
                    addItemButton(for: .folder, root: root, listController: listController, parentModel: parentModel)
                        .disabled(listDisplayModel.isListMode)
                    addItemButton(for: .collection, root: root, listController: listController, parentModel: parentModel)
                        .disabled(listDisplayModel.isListMode)
                    Divider()

                    toggleFolder(listController: listController)
                        .disabled(listModel.selected == nil)

                    Divider()
                } else if let parentModel, parentModel.specialCategory && modal == false {
                    // For special categories (folder/collection), show appropriate add buttons
                    if parentModel.category == .folder {
                        addItemButton(for: .folder, root: root, listController: listController, parentModel: parentModel)
                        addItemButton(for: .collection, root: root, listController: listController, parentModel: parentModel)
                    } else if parentModel.category == root.itemControllable.collectionCategory {
                        // Collections cannot contain folders
                        addItemButton(for: .collection, root: root, listController: listController, parentModel: parentModel)
                    }
                    Divider()
                }
            }
            if parentModel == nil && modal == false {
                Divider()
                CloudFolderScanButton(root: root)
            }
        } label: {
            // A `Label` (not a bare `Image`) so VoiceOver announces this
            // overflow menu's purpose — the toolbar still renders it
            // icon-only by default. See CODE_AUDIT §8.4.
            Label {
                Text("More", bundle: .module)
            } icon: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .popoverTip(MasterRPGTips.organizeContent)
    }
}

private struct ToolbarItemListSecondaryActionMenuView: View {
    let root: any ItemRootControllable
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessible)?
    let modal: Bool

    private var listDisplayModel: ListDisplayModel {
        listController.listDisplayModel
    }

    @ViewBuilder
    var body: some View {
        // A link window (`modal`) has no selection mode. Opacity does not hide an item that
        // collapsed into the overflow menu, so the button has to be left out there; `modal`
        // never changes for a given list, which keeps the toolbar preference tree stable.
        if modal == false {
            // Use opacity/hidden instead of conditional presence to keep the toolbar preference
            // tree stable across selection mode changes and navigation transitions.
            MenuSelectionButtonView(listDisplayModel: listDisplayModel)
                .opacity(listDisplayModel.isSelectionMode ? 0 : 1)
                .allowsHitTesting(!listDisplayModel.isSelectionMode)
                .accessibilityHidden(listDisplayModel.isSelectionMode)
                .disabled(listDisplayModel.isSelectionMode)
        }
        if parentModel == nil && modal == false {
            ControlGroup {
                // `showTip: false` — the `.primaryAction` toolbar item above already carries
                // this same `addItemButton(for: .item)` (and its `.popoverTip`) whenever both
                // are visible at once. Attaching the same Tip's `.popoverTip` to two live
                // anchor views simultaneously confuses TipKit's presentation and crashes with
                // "should have a non-nil sourceView" — only one copy may own the tip.
                addItemButton(for: .item, showTip: false, root: root, listController: listController, parentModel: parentModel)
                addItemButton(for: .folder, showTip: false, root: root, listController: listController, parentModel: parentModel)
                    .disabled(parentModel?.category == root.itemControllable.collectionCategory)
                addItemButton(for: .collection, showTip: false, root: root, listController: listController, parentModel: parentModel)
            }
        }
        ControlGroup {
            CompactDisplayModeToggle(listDisplayModel: listDisplayModel)
            MediumDisplayModeToggle(listDisplayModel: listDisplayModel)
            RegularDisplayModeToggle(listDisplayModel: listDisplayModel)
        }
        if parentModel == nil {
            ControlGroup {
                ListModeToggle(listDisplayModel: listDisplayModel)
                FolderModeToggle(listDisplayModel: listDisplayModel)
            }

            if modal == false {
                ControlGroup {
                    toggleFolder(listController: listController)
                }
                CloudFolderScanButton(root: root)
            }
        }
    }
}

private struct ToolbarItemListDismissButtonView: View {
    let dismissHandler: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismissHandler?()
            dismiss()
        } label: {
            Image(systemName: "checkmark")
        }
        .accessibilityLabel(Text("Done", bundle: .module))
    }
}
