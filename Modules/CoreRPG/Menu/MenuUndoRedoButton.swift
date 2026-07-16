// @copyright André Trettin

import SwiftUI

public struct MenuUndoRedoButton: View {
    public init(root: any ItemRootControllable) {
        self.root = root
    }
    
    let root: any ItemRootControllable

    public var body: some View {
        ControlGroup {
            UndoButton(root: root)
            RedoButton(root: root)
        }
    }
}

#Preview { MenuUndoRedoButton(root: ItemRootController.fake) }
