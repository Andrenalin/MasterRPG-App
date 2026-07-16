// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct SpaceActionButton: View {
    let root: any ItemRootControllable
    let scenesManager: ScenesManager

    var body: some View {
        Button {
            if root.viewControllable.hasCustomSpaceAction {
                root.navigationModel.triggerSpaceAction = true
            } else {
                viewItem()
            }
        } label: {
            Label {
                labelText
            } icon: {
                Image(systemName: root.viewControllable.hasCustomSpaceAction ? "play.fill" : "eye")
            }
        }
        .keyboardShortcut(.return, modifiers: [.command, .shift])
        .disabled(root.currentSelectedItemId == nil)
    }

    private func viewItem() {
        let fileModel = root.openFileWindowModel
        guard fileModel.enabled else { return }
#if os(macOS) || os(visionOS)
        if let windowId = fileModel.windowId {
            scenesManager.openWindow(SceneId(rawValue: windowId), selection: WindowItemSelection(itemId: fileModel.itemId, entryId: fileModel.entryId))
            return
        }
#endif
        withAnimation { fileModel.showItem.toggle() }
    }

    private var labelText: Text {
        let name = item?.name ?? ""
        if root.viewControllable.hasCustomSpaceAction {
            return Text("\(root.configurable.module == .audio ? "Play" : "Roll") \(name)", bundle: .module)
        }
        return Text("View \(name)", bundle: .module)
    }

    private var item: (any ItemDataAccessable)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

#Preview {
    SpaceActionButton(root: ItemRootController.fake, scenesManager: ScenesManager())
}
#endif
